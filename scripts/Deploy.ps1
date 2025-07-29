param(
    [string]$YamlFilePath = "repos.yml"
)

function Parse-Yaml {
    param($Path)
    # Requires PowerShell 7 and 'powershell-yaml' module
    Import-Module powershell-yaml
    $data = ConvertFrom-Yaml (Get-Content $Path -Raw)
    return $data.repositories
}

function Get-GitHub-Issues {
    param($Repo)
    $headers = @{
        Authorization = "token $($env:GITHUB_TOKEN)"
        Accept        = "application/vnd.github.v3+json"
    }
    $url = "https://api.github.com/repos/$Repo/issues?state=all&per_page=100"
    Invoke-RestMethod -Uri $url -Headers $headers
}

function Parse-Issue-Body {
    param($Body)
    $pattern = 'yml:(?<yml>[^,]+),\s*code:(?<code>[^,]+),\s*parsetext:(?<parsetext>[^\s]+)'
    if ($Body -match $pattern) {
        return @{
            yml       = $matches['yml']
            code      = $matches['code']
            parsetext = $matches['parsetext']
        }
    }
    return $null
}

function Decode-Code {
    param($Code, $Salt)
    # Example: Base64 decode, then XOR with salt chars (simple demo, adapt as needed)
    $bytes = [System.Convert]::FromBase64String($Code)
    $saltBytes = [System.Text.Encoding]::UTF8.GetBytes($Salt)
    for ($i=0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = $bytes[$i] -bxor $saltBytes[$i % $saltBytes.Length]
    }
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Trigger-GitHub-Workflow {
    param($Repo, $WorkflowFile, $Inputs)
    $headers = @{
        Authorization = "token $($env:GITHUB_TOKEN)"
        Accept        = "application/vnd.github.v3+json"
    }
    $url = "https://api.github.com/repos/$Repo/actions/workflows/$WorkflowFile/dispatches"
    $body = @{
        ref = "main"  # or the branch you'd like
        inputs = $Inputs
    } | ConvertTo-Json
    Invoke-RestMethod -Uri $url -Headers $headers -Method POST -Body $body
}

# Main Logic
$repos = Parse-Yaml -Path $YamlFilePath
foreach ($repo in $repos) {
    Write-Host "Processing repo: $repo"
    $issues = Get-GitHub-Issues -Repo $repo
    foreach ($issue in $issues) {
        $parsed = Parse-Issue-Body -Body $issue.body
        if ($parsed) {
            Write-Host "Found pattern in issue #$($issue.number): $($parsed.yml)"
            $decoded = Decode-Code -Code $parsed.code -Salt $parsed.parsetext
            Write-Host "Decoded code: $decoded"
            # Optionally pass decoded value as input to workflow
            Trigger-GitHub-Workflow -Repo $repo -WorkflowFile $parsed.yml -Inputs @{secret = $decoded}
        }
    }
}
