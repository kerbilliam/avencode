function Get-MKVPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Expressions,
        
        [bool]$LPath = $false
    )
    
    $expanded_paths = @()
    
    foreach ($exp in $Expressions) {
        $res_errors = $null
        
        if ($LPath) {
            $resolved = Resolve-Path -LiteralPath $exp -ErrorVariable res_errors -ErrorAction SilentlyContinue
        } else {
            $resolved = Resolve-Path -Path $exp -ErrorVariable res_errors -ErrorAction SilentlyContinue
        }

        $resolved | ForEach-Object {
            $path = $_.ProviderPath
            if ((Test-Path -PathType Leaf -LiteralPath $path) -and ($path -like '*.mkv')) {
                $expanded_paths += $path
            } else {
                Write-Warning "Skipping '$path': Not a valid .mkv file."
            }
        }

        if ($res_errors) {
            Write-Warning "Could not resolve path '$exp'. Skipping..."
        }
    }
    
    return $expanded_paths
}

$fname = 'hello[1-9].mkv'
$LPath = $true
New-Item -Name $fname > $null

Write-Host 'without litpath'
$paths = Get-MKVPaths -Expressions $fname
Write-Host "paths: $paths"

Write-Host 'with litpath'
$paths = Get-MKVPaths -Expressions $fname -LPath $LPath
Write-Host "paths: $paths"

Remove-Item -LiteralPath $fname

$fname = '*.ps1'

Write-Host 'without litpath'
$paths = Get-MKVPaths -Expressions $fname
Write-Host "paths: $paths"

Write-Host 'with litpath'
$paths = Get-MKVPaths -Expressions $fname -LPath $LPath
Write-Host "paths: $paths"