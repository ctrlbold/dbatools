function Invoke-DbaDbDataMasking {
    <#
    .SYNOPSIS
        Invoke-DbaDbDataMasking generates random data for tables

    .DESCRIPTION
        Invoke-DbaDbDataMasking is able to generate random data for tables.
        It will use a configuration file that can be made manually or generated using New-PSDCMaskingConfiguration

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Credential
        Allows you to login to servers or folders
        To use:
        $scred = Get-Credential, then pass $scred object to the -Credential parameter.

    .PARAMETER Database
        Databases to process through

    .PARAMETER Table
        Tables to process. By default all the tables will be processed

    .PARAMETER Column
        Columns to process. By default all the columns will be processed

    .PARAMETER FilePath
        Configuration file that contains the which tables and columns need to be masked

    .PARAMETER Query
        If you would like to mask only a subset of a table, use the Query parameter, otherwise all data will be masked.

    .PARAMETER Locale
        Set the local to enable certain settings in the masking

    .PARAMETER MaxValue
        Force a max length of strings instead of relying on datatype maxes. Note if a string datatype has a lower MaxValue, that will be used instead.

        Useful for adhoc updates and testing, otherwise, the config file should be used.

    .PARAMETER Force
        Forcefully execute commands when needed

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DataMasking, Database
        Author: Sander Stad (@sqlstad, sqlstad.nl) | Chrissy LeMaire (@cl, netnerds.net)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbDataMasking

    .EXAMPLE
        Invoke-DbaDbDataMasking -SqlInstance SQLDB1 -Database DB1 -FilePath C:\Temp\DB1.tables.json

        Apply the data masking configuration from the file "DB1.tables.json" to the database
    #>
    [CmdLetBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [string[]]$Database,
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias('Path', 'FullName')]
        [object]$FilePath,
        [string]$Locale = 'en',
        [string]$Query,
        [switch]$Force,
        [int]$MaxValue,
        [switch]$EnableException
    )
    begin {
        # Set defaults
        $charString = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

        # Create the faker objects
        Add-Type -Path (Resolve-Path -Path "$script:PSModuleRoot\bin\datamasking\Bogus.dll")
        $faker = New-Object Bogus.Faker($Locale)
    }

    process {
        if (Test-FunctionInterrupt) {
            return
        }

        # Check if the destination is accessible
        if (-not (Test-Path -Path $FilePath -Credential $Credential)) {
            Stop-Function -Message "Could not find masking config file" -ErrorRecord $_ -Target $FilePath
            return
        }

        # Get all the items that should be processed
        try {
            $tables = Get-Content -Path $FilePath -Credential $Credential -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Stop-Function -Message "Could not parse masking config file" -ErrorRecord $_ -Target $FilePath
            return
        }

        foreach ($tabletest in $tables.Tables) {
            foreach ($columntest in $tabletest.Columns) {
                if ($columntest.ColumnType -in 'hierarchyid', 'geography') {
                    Stop-Function -Message "$($columntest.ColumnType) is not supported, please remove the column $($columntest.Name) from the $($tabletest.Name) table" -Target $tables
                }
            }
        }

        if (Test-FunctionInterrupt) {
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($db in (Get-DbaDatabase -SqlInstance $server -Database $Database)) {

                foreach ($table in $tables.Tables) {
                    if ($table.Name -in $db.Tables.Name) {
                        try {
                            if (-not (Test-Bound -ParameterName Query)) {
                                $query = "SELECT * FROM [$($table.Schema)].[$($table.Name)]"
                            }

                            $data = $db.Query($query) | ConvertTo-DbaDataTable
                        } catch {
                            Stop-Function -Message "Something went wrong retrieving the data from table $($table.Name)" -Target $Database
                        }

                        # Loop through each of the rows and change them
                        foreach ($row in $data.Rows) {
                            $updates = $wheres = @()

                            foreach ($column in $table.Columns) {
                                # make sure max is good
                                if ($MaxValue) {
                                    if ($column.MaxValue -le $MaxValue) {
                                        $max = $column.MaxValue
                                    } else {
                                        $max = $MaxValue
                                    }
                                }

                                if (-not $column.MaxValue -and -not (Test-Bound -ParameterName MaxValue)) {
                                    $max = 10
                                }

                                $newValue = switch ($column.MaskingType.ToLower()) {
                                    { $_ -in 'name', 'address', 'finance' } {
                                        $faker.$($column.MaskingType).$($column.SubType)()
                                    }
                                    { $_ -in 'date', 'datetime', 'datetime2', 'smalldatetime' } {
                                        ($faker.Date.Past()).ToString("yyyyMMdd")
                                    }
                                    'number' {
                                        $faker.$($column.MaskingType).$($column.SubType)($column.MaxValue)
                                    }
                                    'shuffle' {
                                        ($row.($column.Name) -split '' | Sort-Object {
                                                Get-Random
                                            }) -join ''
                                    }
                                    'string' {
                                        $faker.$($column.MaskingType).String2($max, $charString)
                                    }
                                    default {
                                        $null
                                    }
                                }

                                if (-not $newValue) {
                                    $newValue = switch ($column.ColumnType) {
                                        { $_ -in 'date', 'datetime', 'datetime2', 'smalldatetime' } {
                                            ($faker.Date.Past()).ToString("yyyyMMdd")
                                        }
                                        'money' {
                                            $faker.Finance.Amount(0, $max)
                                        }
                                        'smallint' {
                                            $faker.System.Random.Int(-32768, 32767)
                                        }
                                        'bit' {
                                            $faker.System.Random.Bool()
                                        }
                                        'uniqueidentifier' {
                                            $faker.System.Random.Guid().Guid
                                        }
                                        default {
                                            $faker.Random.String2(0, $max, $charString)
                                        }
                                    }
                                }

                                if ($column.ColumnType -in 'uniqueidentifier') {
                                    $updates += "[$($column.Name)] = '$newValue'"
                                } elseif ($column.ColumnType -match 'int' ) {
                                    $updates += "[$($column.Name)] = $newValue"
                                } else {
                                    $newValue = ($newValue).Tostring().Replace("'", "''")
                                    $updates += "[$($column.Name)] = '$newValue'"
                                }

                                if ($column.ColumnType -notin 'xml', 'geography') {
                                    $oldValue = ($row.$($column.Name)).Tostring().Replace("'", "''")
                                    $wheres += "[$($column.Name)] = '$oldValue'"
                                }
                            }

                            $updatequery = "UPDATE [$($table.Schema)].[$($table.Name)] SET $($updates -join ', ') WHERE $($wheres -join ' AND ')"

                            try {
                                Write-Message -Level Debug -Message $updatequery
                                $db.Query($updatequery)
                                [pscustomobject]@{
                                    SqlInstance = $db.Parent.Name
                                    Database    = $db.Name
                                    Schema      = $table.Schema
                                    Table       = $table.Name
                                    Query       = $updatequery
                                    Status      = "Success"
                                } | Select-DefaultView -ExcludeProperty Query
                            } catch {
                                Write-Message -Level Verbose -Message "$updatequery"
                                Stop-Function -Message "Could not execute query when updating $($table.Schema).$($table.Name)" -Target $updatequery -Continue -ErrorRecord $_
                            }
                        }
                    } else {
                        Stop-Function -Message "Table $($table.Name) is not present" -Target $Database -Continue
                    }
                }
            }
        }
    }
}