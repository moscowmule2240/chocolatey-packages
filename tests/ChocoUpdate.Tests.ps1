BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'ChocoUpdate.psm1') -Force
}

Describe 'Get-DualArchSearchReplace' {
    It 'produces replacements for all four variables' {
        $latest = @{
            URL64         = 'https://example.test/app-x64.exe'
            Checksum64    = 'aaaa'
            URLArm64      = 'https://example.test/app-arm64.exe'
            ChecksumArm64 = 'bbbb'
        }

        $sr = Get-DualArchSearchReplace -Latest $latest
        $rules = $sr['tools\chocolateyinstall.ps1']

        $rules.Count | Should -Be 4
        ($rules.Values -join ' ') | Should -BeLike '*app-x64.exe*'
        ($rules.Values -join ' ') | Should -BeLike '*app-arm64.exe*'
        ($rules.Values -join ' ') | Should -BeLike '*aaaa*'
        ($rules.Values -join ' ') | Should -BeLike '*bbbb*'
    }

    It 'rewrites a real install script line' {
        $latest = @{
            URL64 = 'https://example.test/new.exe'; Checksum64 = 'newsum'
            URLArm64 = 'https://example.test/new-arm.exe'; ChecksumArm64 = 'newarmsum'
        }
        $sr = Get-DualArchSearchReplace -Latest $latest
        $line = "  `$url64      = 'https://example.test/old.exe'"

        foreach ($pattern in $sr['tools\chocolateyinstall.ps1'].Keys) {
            $line = $line -replace $pattern, $sr['tools\chocolateyinstall.ps1'][$pattern]
        }

        $line | Should -BeLike "*'https://example.test/new.exe'*"
        $line | Should -Not -BeLike '*old.exe*'
    }

    It 'does not let the x64 pattern touch the arm64 line' {
        $latest = @{
            URL64 = 'https://example.test/new.exe'; Checksum64 = 'newsum'
            URLArm64 = 'https://example.test/new-arm.exe'; ChecksumArm64 = 'newarmsum'
        }
        $sr = Get-DualArchSearchReplace -Latest $latest
        $armLine = "  `$urlArm64   = 'https://example.test/old-arm.exe'"

        $x64Pattern = $sr['tools\chocolateyinstall.ps1'].Keys |
                      Where-Object { $_ -like '*url64*' -and $_ -notlike '*Arm64*' }
        ($armLine -replace $x64Pattern, 'REPLACED') | Should -Be $armLine
    }
}

Describe 'Get-ValidatedContent' {
    It 'returns the validator result on the first success' {
        Mock -ModuleName ChocoUpdate Invoke-WebRequest {
            [pscustomobject]@{ Content = 'version: 1.2.3'; StatusCode = 200 }
        }

        $result = Get-ValidatedContent -Uri 'https://example.test/feed' -What 'the version' -Validate {
            param($body)
            $m = [regex]::Match($body, 'version: (\d+\.\d+\.\d+)')
            if ($m.Success) { $m.Groups[1].Value } else { $null }
        }

        $result | Should -Be '1.2.3'
    }

    It 'decodes a byte[] body as UTF-8' {
        Mock -ModuleName ChocoUpdate Invoke-WebRequest {
            [pscustomobject]@{
                Content    = [System.Text.Encoding]::UTF8.GetBytes('version: 9.9.9')
                StatusCode = 200
            }
        }

        $result = Get-ValidatedContent -Uri 'https://example.test/feed' -What 'the version' -Validate {
            param($body)
            $m = [regex]::Match($body, 'version: (\d+\.\d+\.\d+)')
            if ($m.Success) { $m.Groups[1].Value } else { $null }
        }

        $result | Should -Be '9.9.9'
    }

    It 'retries when the validator rejects the body, then succeeds' {
        $script:calls = 0
        Mock -ModuleName ChocoUpdate Start-Sleep { }
        Mock -ModuleName ChocoUpdate Invoke-WebRequest {
            $script:calls++
            $body = if ($script:calls -eq 1) { 'truncated' } else { 'value: ok' }
            [pscustomobject]@{ Content = $body; StatusCode = 200 }
        }

        $result = Get-ValidatedContent -Uri 'https://example.test/feed' -What 'the value' -Validate {
            param($body)
            if ($body -match 'value: (\w+)') { $Matches[1] } else { $null }
        }

        $result       | Should -Be 'ok'
        $script:calls | Should -Be 2
    }

    It 'throws with status, length and the body tail after every attempt fails' {
        Mock -ModuleName ChocoUpdate Start-Sleep { }
        Mock -ModuleName ChocoUpdate Invoke-WebRequest {
            [pscustomobject]@{ Content = 'nothing useful here'; StatusCode = 200 }
        }

        { Get-ValidatedContent -Uri 'https://example.test/feed' -What 'the value' -Validate { $null } } |
            Should -Throw -ExpectedMessage '*HTTP 200*'
    }

    It 'retries a request that throws, then succeeds' {
        $script:attempts = 0
        Mock -ModuleName ChocoUpdate Start-Sleep { }
        Mock -ModuleName ChocoUpdate Invoke-WebRequest {
            $script:attempts++
            if ($script:attempts -eq 1) { throw 'connection reset' }
            [pscustomobject]@{ Content = 'value: recovered'; StatusCode = 200 }
        }

        $result = Get-ValidatedContent -Uri 'https://example.test/feed' -What 'the value' -Validate {
            param($body)
            if ($body -match 'value: (\w+)') { $Matches[1] } else { $null }
        }

        $result | Should -Be 'recovered'
    }

    It 'sends the headers it is given' {
        $script:seen = $null
        Mock -ModuleName ChocoUpdate Invoke-WebRequest {
            param($Uri, $Headers, $UseBasicParsing)
            $script:seen = $Headers
            [pscustomobject]@{ Content = 'ok'; StatusCode = 200 }
        }

        Get-ValidatedContent -Uri 'https://example.test/x' -What 'anything' `
            -Headers @{ 'Authorization' = 'Bearer t' } -Validate { param($b) $b } | Out-Null

        $script:seen['Authorization'] | Should -Be 'Bearer t'
    }
}
