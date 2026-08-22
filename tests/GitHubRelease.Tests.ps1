BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'ChocoUpdate.psm1')   -Force
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'GitHubRelease.psm1') -Force

    $script:sample = [pscustomobject]@{
        tag_name = 'v1.5.6'
        assets   = @(
            [pscustomobject]@{
                name   = 'jadx-1.5.6.zip'
                digest = 'sha256:545ea2be9c242511bc145755cf4bda2485ade42966e096f8b4d3da2a230e8974'
                browser_download_url = 'https://github.com/skylot/jadx/releases/download/v1.5.6/jadx-1.5.6.zip'
            },
            [pscustomobject]@{
                name   = 'jadx-gui-1.5.6-win.zip'
                digest = 'sha256:6e070b197d4e40275d10f6559a1661bdd2e2bb325e9ef4181c7ac1286b274d99'
                browser_download_url = 'https://github.com/skylot/jadx/releases/download/v1.5.6/jadx-gui-1.5.6-win.zip'
            },
            [pscustomobject]@{
                name   = 'jadx-gui-1.5.6-with-jre-win.zip'
                digest = 'sha256:56a870460d03d3d6f22eb0908c33e298bc7370c952a6b7fa48c22a187ecd690b'
                browser_download_url = 'https://github.com/skylot/jadx/releases/download/v1.5.6/jadx-gui-1.5.6-with-jre-win.zip'
            }
        )
    }
}

Describe 'Get-ReleaseVersion' {
    It 'strips a leading v' {
        Get-ReleaseVersion -Release $script:sample | Should -Be '1.5.6'
    }

    It 'accepts a tag with no v' {
        Get-ReleaseVersion -Release ([pscustomobject]@{ tag_name = '2.0.1' }) | Should -Be '2.0.1'
    }

    It 'accepts a two-component version' {
        Get-ReleaseVersion -Release ([pscustomobject]@{ tag_name = 'v3.1' }) | Should -Be '3.1'
    }

    It 'throws on a tag that carries no version' {
        { Get-ReleaseVersion -Release ([pscustomobject]@{ tag_name = 'nightly' }) } |
            Should -Throw -ExpectedMessage '*nightly*'
    }

    It 'throws on a prerelease suffix rather than truncating it' {
        { Get-ReleaseVersion -Release ([pscustomobject]@{ tag_name = 'v1.5.6-rc1' }) } |
            Should -Throw -ExpectedMessage '*v1.5.6-rc1*'
    }
}

Describe 'Select-ReleaseAsset' {
    It 'returns the one asset whose name matches exactly' {
        $asset = Select-ReleaseAsset -Release $script:sample -Name 'jadx-1.5.6.zip'
        $asset.browser_download_url | Should -BeLike '*/jadx-1.5.6.zip'
    }

    It 'does not match on a prefix' {
        { Select-ReleaseAsset -Release $script:sample -Name 'jadx-1.5.6' } |
            Should -Throw -ExpectedMessage '*found 0*'
    }

    It 'does not pick the jre-bundled archive when asked for the plain one' {
        $asset = Select-ReleaseAsset -Release $script:sample -Name 'jadx-1.5.6.zip'
        $asset.name | Should -Not -BeLike '*with-jre*'
    }

    It 'lists the available assets when nothing matches' {
        { Select-ReleaseAsset -Release $script:sample -Name 'missing.zip' } |
            Should -Throw -ExpectedMessage '*jadx-gui-1.5.6-win.zip*'
    }

    It 'throws when more than one asset matches' {
        $dup = [pscustomobject]@{
            tag_name = 'v1.0.0'
            assets   = @(
                [pscustomobject]@{ name = 'same.zip' },
                [pscustomobject]@{ name = 'same.zip' }
            )
        }
        { Select-ReleaseAsset -Release $dup -Name 'same.zip' } |
            Should -Throw -ExpectedMessage '*found 2*'
    }
}

Describe 'Get-AssetChecksum' {
    It 'returns the hex digest without the algorithm prefix' {
        $asset = Select-ReleaseAsset -Release $script:sample -Name 'jadx-1.5.6.zip'
        Get-AssetChecksum -Asset $asset |
            Should -Be '545ea2be9c242511bc145755cf4bda2485ade42966e096f8b4d3da2a230e8974'
    }

    It 'lowercases an uppercase digest' {
        $asset = [pscustomobject]@{ name = 'x.zip'; digest = 'sha256:' + ('A' * 64) }
        Get-AssetChecksum -Asset $asset | Should -Be ('a' * 64)
    }

    It 'returns null when the asset has no digest' {
        Get-AssetChecksum -Asset ([pscustomobject]@{ name = 'x.zip' }) | Should -BeNullOrEmpty
    }

    It 'throws on a digest algorithm it cannot read' {
        { Get-AssetChecksum -Asset ([pscustomobject]@{ name = 'x.zip'; digest = 'md5:abc' }) } |
            Should -Throw -ExpectedMessage '*md5:abc*'
    }
}

Describe 'Get-GitHubLatestRelease' {
    It 'parses the JSON body and returns the release' {
        Mock -ModuleName ChocoUpdate Invoke-WebRequest {
            [pscustomobject]@{
                StatusCode = 200
                Content    = '{"tag_name":"v1.5.6","assets":[{"name":"jadx-1.5.6.zip"}]}'
            }
        }

        $release = Get-GitHubLatestRelease -Repo 'skylot/jadx'
        $release.tag_name       | Should -Be 'v1.5.6'
        $release.assets[0].name | Should -Be 'jadx-1.5.6.zip'
    }

    It 'sends an Authorization header when GITHUB_TOKEN is set' {
        $script:seen = $null
        Mock -ModuleName ChocoUpdate Invoke-WebRequest {
            param($Uri, $Headers, $UseBasicParsing)
            $script:seen = $Headers
            [pscustomobject]@{ StatusCode = 200; Content = '{"tag_name":"v1.0.0","assets":[{"name":"a"}]}' }
        }

        $env:GITHUB_TOKEN = 'test-token'
        try {
            Get-GitHubLatestRelease -Repo 'owner/repo' | Out-Null
        } finally {
            Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
        }

        $script:seen['Authorization'] | Should -Be 'Bearer test-token'
        $script:seen['Accept']        | Should -Be 'application/vnd.github+json'
    }

    It 'omits Authorization when GITHUB_TOKEN is absent' {
        $script:seen = $null
        Mock -ModuleName ChocoUpdate Invoke-WebRequest {
            param($Uri, $Headers, $UseBasicParsing)
            $script:seen = $Headers
            [pscustomobject]@{ StatusCode = 200; Content = '{"tag_name":"v1.0.0","assets":[{"name":"a"}]}' }
        }

        Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
        Get-GitHubLatestRelease -Repo 'owner/repo' | Out-Null

        $script:seen.ContainsKey('Authorization') | Should -BeFalse
    }

    It 'rejects a body that is not JSON, and retries' {
        Mock -ModuleName ChocoUpdate Start-Sleep { }
        $script:tries = 0
        Mock -ModuleName ChocoUpdate Invoke-WebRequest {
            $script:tries++
            $body = if ($script:tries -eq 1) { '<html>rate limited</html>' }
                    else { '{"tag_name":"v2.0.0","assets":[{"name":"a"}]}' }
            [pscustomobject]@{ StatusCode = 200; Content = $body }
        }

        $release = Get-GitHubLatestRelease -Repo 'owner/repo'
        $release.tag_name | Should -Be 'v2.0.0'
        $script:tries     | Should -Be 2
    }
}
