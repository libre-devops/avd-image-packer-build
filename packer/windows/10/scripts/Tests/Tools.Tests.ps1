Describe "Azure Cosmos DB Emulator" {
    $cosmosDbEmulatorRegKey = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | Get-ItemProperty | Where-Object { $_.DisplayName -eq 'Azure Cosmos DB Emulator' }
    $installDir = $cosmosDbEmulatorRegKey.InstallLocation

    It "Azure Cosmos DB Emulator install location registry key exists" -TestCases @{installDir = $installDir} {
        $installDir | Should -Not -BeNullOrEmpty
    }

    It "Azure Cosmos DB Emulator exe file exists" -TestCases @{installDir = $installDir} {
        $exeFilePath = Join-Path $installDir 'CosmosDB.Emulator.exe'
        $exeFilePath | Should -Exist
    }
}

Describe "DACFx" {
    It "DACFx" {
        (Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*).DisplayName -Contains "Microsoft SQL Server Data-Tier Application Framework" | Should -BeTrue
        $sqlPackagePath = 'C:\Program Files\Microsoft SQL Server\160\DAC\bin\SqlPackage.exe'
        "${sqlPackagePath}" | Should -Exist
    }
}


Describe "KubernetesTools" {
    It "Kind" {
        "kind version" | Should -ReturnZeroExitCode
    }

    It "kubectl" {
        "kubectl version --client=true --short=true" | Should -ReturnZeroExitCode
    }

    It "Helm" {
        "helm version --short" | Should -ReturnZeroExitCode
    }

    It "minikube" {
        "minikube version --short" | Should -ReturnZeroExitCode
    }
}


Describe "NET48" {
    It "NET48" {
        Get-ChildItem -Path "${env:ProgramFiles(x86)}\Microsoft SDKs\Windows\*\*\NETFX 4.8 Tools" -Directory | Should -HaveCount 1
    }
}

Describe "PowerShell Core" {
    It "pwsh" {
        "pwsh --version" | Should -ReturnZeroExitCode
    }

    It "Execute 2+2 command" {
        pwsh -Command "2+2" | Should -BeExactly 4
    }
}

Describe "WebPlatformInstaller" {
    It "WebPlatformInstaller" {
        "WebPICMD" | Should -ReturnZeroExitCode
    }
}

Describe "Pipx" {
    It "Pipx" {
        "pipx --version" | Should -ReturnZeroExitCode
    }
}

Describe "SQL OLEDB Driver" {
    It "SQL OLEDB Driver" {
        "HKLM:\SOFTWARE\Microsoft\MSOLEDBSQL" | Should -Exist
    }
}

Describe "OpenSSL" {
    It "OpenSSL" {
        $OpenSSLVersion = (Get-ToolsetContent).openssl.version
        openssl version | Should -BeLike "* ${OpenSSLVersion}*"
    }
}
