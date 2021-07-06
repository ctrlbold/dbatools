function Get-DecryptedObject {
    <#
            .SYNOPSIS
                Internal function.

                This function is heavily based on Antti Rantasaari's script at http://goo.gl/wpqSib
                Antti Rantasaari 2014, NetSPI
                License: BSD 3-Clause http://opensource.org/licenses/BSD-3-Clause
    #>
    param (
        [Parameter(Mandatory)]
        [Microsoft.SqlServer.Management.Smo.Server]$SqlInstance,
        [Parameter(Mandatory)]
        [ValidateSet("LinkedServer", "Credential")]
        [string]$Type,
        [switch]$EnableException
    )

    $server = $SqlInstance
    $sourceName = $server.Name

    # Query Service Master Key from the database - remove padding from the key
    # key_id 102 eq service master key, thumbprint 3 means encrypted with machinekey
    Write-Message -Level Verbose -Message "Querying service master key"
    $sql = "SELECT substring(crypt_property,9,len(crypt_property)-8) as smk FROM sys.key_encryptions WHERE key_id=102 and (thumbprint=0x03 or thumbprint=0x0300000001)"
    try {
        $smkbytes = $server.Query($sql).smk
    } catch {
        Stop-Function -Message "Can't execute query on $sourcename" -Target $server -ErrorRecord $_
        return
    }

    try {
        $resolved = Resolve-DbaNetworkName -ComputerName $server -Credential $Credential -EnableException
        $fullComputerName = $resolved.FullComputerName
    } catch {
        Stop-Function -Message "Error occurred while resolving $server" -Category ConnectionError -ErrorRecord $_ -Target $server
        return
    }
    $instance = $server.InstanceName
    $serviceInstanceId = $server.ServiceInstanceId

    Write-Message -Level Verbose -Message "Get entropy from the registry - hopefully finds the right SQL server instance"

    try {
        [byte[]]$entropy = Invoke-Command2 -Raw -Credential $Credential -ComputerName $fullComputerName -argumentlist $serviceInstanceId {
            $serviceInstanceId = $args[0]
            $entropy = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$serviceInstanceId\Security\" -ErrorAction Stop).Entropy
            return $entropy
        }
    } catch {
        Stop-Function -Message "Can't access registry keys on $sourceName. Do you have administrative access to the Windows registry on $SqlInstance Otherwise, we're out of ideas." -Target $source
        return
    }

    Write-Message -Level Verbose -Message "Decrypt the service master key"
    try {
        $serviceKey = Invoke-Command2 -Raw -Credential $Credential -ComputerName $fullComputerName -ArgumentList $smkbytes, $Entropy {
            Add-Type -AssemblyName System.Security
            Add-Type -AssemblyName System.Core
            $smkbytes = $args[0]; $Entropy = $args[1]
            $serviceKey = [System.Security.Cryptography.ProtectedData]::Unprotect($smkbytes, $Entropy, 'LocalMachine')
            return $serviceKey
        }
    } catch {
        Stop-Function -Message "Can't unprotect registry data on $sourcename. Do you have administrative access to the Windows registry on $sourcename? Otherwise, we're out of ideas." -Target $source
        return
    }

    # Choose the encryption algorithm based on the SMK length - 3DES for 2008, AES for 2012
    # Choose IV length based on the algorithm
    Write-Message -Level Verbose -Message "Choose the encryption algorithm based on the SMK length - 3DES for 2008, AES for 2012"

    if (($serviceKey.Length -ne 16) -and ($serviceKey.Length -ne 32)) {
        Write-Message -Level Verbose -Message "ServiceKey found: $serviceKey.Length"
        Stop-Function -Message "Unknown key size. Do you have administrative access to the Windows registry on $sourcename? Otherwise, we're out of ideas." -Target $source
        return
    }

    if ($serviceKey.Length -eq 16) {
        $decryptor = New-Object System.Security.Cryptography.TripleDESCryptoServiceProvider
        $ivlen = 8
    } elseif ($serviceKey.Length -eq 32) {
        $decryptor = New-Object System.Security.Cryptography.AESCryptoServiceProvider
        $ivlen = 16
    }

    <#
        Query link server password information from the Db.
        Remove header from pwdhash, extract IV (as iv) and ciphertext (as pass)
        Ignore links with blank credentials (integrated auth ?)
    #>

    Write-Message -Level Verbose -Message "Query link server password information from the Db."

    try {
        if (-not $server.IsClustered) {
            $connString = "Server=ADMIN:$fullComputerName\$instance;Trusted_Connection=True;Pooling=false"
        } else {
            $dacEnabled = $server.Configuration.RemoteDacConnectionsEnabled.ConfigValue

            if ($dacEnabled -eq $false) {
                If ($Pscmdlet.ShouldProcess($server.Name, "Enabling DAC on clustered instance.")) {
                    Write-Message -Level Verbose -Message "DAC must be enabled for clusters, even when accessed from active node. Enabling."
                    $server.Configuration.RemoteDacConnectionsEnabled.ConfigValue = $true
                    $server.Configuration.Alter()
                }
            }

            $connString = "Server=ADMIN:$sourceName;Trusted_Connection=True;Pooling=false;"
        }
    } catch {
        Stop-Function -Message "Failure enabling DAC on $sourcename" -Target $source -ErrorRecord $_
    }

    <# NOTE: This query is accessing syslnklgns table. Can only be done via the DAC connection #>

    $sql = switch ($Type) {
        "LinkedServer" {
            "SELECT sysservers.srvname,
                syslnklgns.name,
                substring(syslnklgns.pwdhash,5,$ivlen) iv,
                substring(syslnklgns.pwdhash,$($ivlen + 5),
                len(syslnklgns.pwdhash)-$($ivlen + 4)) pass
            FROM master.sys.syslnklgns
                inner join master.sys.sysservers
                on syslnklgns.srvid=sysservers.srvid
            WHERE len(pwdhash) > 0"
        }
        "Credential" {
            "SELECT QUOTENAME(name) AS name,credential_identity,substring(imageval,5,$ivlen) iv, substring(imageval,$($ivlen + 5),len(imageval)-$($ivlen + 4)) pass from sys.credentials cred inner join sys.sysobjvalues obj on cred.credential_id = obj.objid where valclass=28 and valnum=2"
        }
    }

    Write-Message -Level Debug -Message $sql

    try {
        $results = Invoke-Command2 -ErrorAction Stop -Raw -Credential $Credential -ComputerName $fullComputerName -ArgumentList $connString, $sql {
            $connString = $args[0]
            $sql = $args[1]
            $conn = New-Object System.Data.SqlClient.SQLConnection($connString)
            $cmd = New-Object System.Data.SqlClient.SqlCommand($sql, $conn)
            $dt = New-Object System.Data.DataTable
            $conn.open()
            $dt.Load($cmd.ExecuteReader())
            $conn.Close()
            $conn.Dispose()
            return $dt
        }
    } catch {
        try {
            $conn.Close()
            $conn.Dispose()
        } catch {
            $null = 1
        }
        Stop-Function -Message "Can't establish local DAC connection on $sourcename." -Target $server -ErrorRecord $_
        return
    }


    if ($server.IsClustered -and $dacEnabled -eq $false) {
        If ($Pscmdlet.ShouldProcess($server.Name, "Disabling DAC on clustered instance.")) {
            try {
                Write-Message -Level Verbose -Message "Setting DAC config back to 0."
                $server.Configuration.RemoteDacConnectionsEnabled.ConfigValue = $false
                $server.Configuration.Alter()
            } catch {
                Stop-Function -Message "Can't establish local DAC connection on $sourcename" -Target $server -ErrorRecord $_
                return
            }
        }
    }

    Write-Message -Level Verbose -Message "Go through each row in results"
    foreach ($result in $results) {
        # decrypt the password using the service master key and the extracted IV
        $decryptor.Padding = "None"
        $decrypt = $decryptor.Createdecryptor($serviceKey, $result.iv)
        $stream = New-Object System.IO.MemoryStream ( , $result.pass)
        $crypto = New-Object System.Security.Cryptography.CryptoStream $stream, $decrypt, "Write"

        $crypto.Write($result.pass, 0, $result.pass.Length)
        [byte[]]$decrypted = $stream.ToArray()

        # convert decrypted password to unicode
        $encode = New-Object System.Text.UnicodeEncoding

        # Print results - removing the weird padding (8 bytes in the front, some bytes at the end)...
        # Might cause problems but so far seems to work.. may be dependant on SQL server version...
        # If problems arise remove the next three lines..
        $i = 8; foreach ($b in $decrypted) { if ($decrypted[$i] -ne 0 -and $decrypted[$i + 1] -ne 0 -or $i -eq $decrypted.Length) { $i -= 1; break; }; $i += 1; }
        $decrypted = $decrypted[8 .. $i]

        if ($Type -eq "LinkedServer") {
            $name = $result.srvname
            $identity = $result.Name
        } else {
            $name = $result.name
            $identity = $result.credential_identity
        }
        [pscustomobject]@{
            Name     = $name
            Identity = $identity
            Password = $encode.GetString($decrypted)
        }
    }
}