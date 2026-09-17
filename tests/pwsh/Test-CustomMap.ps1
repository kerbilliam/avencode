function Test-CustomMap {
    [CmdletBinding()]    
    param(
        [Parameter(Mandatory)]
        [int[]]$MapIndexes
    )
    
    if ($MapIndexes -notcontains 0) {
        Write-Warning "Custom Index: '$($MapIndexes -join ',')' Does not contain Index 0"
        Write-Host 'Video streams typically start at index 0. Are you sure you want to continue?'

        $confrimation = Read-Host "Do you want to continue? [y/N]"
        if ($confrimation.ToLower() -ne 'y') {
            return $false
        }
    }
    
    return $true
}

$idxs = 1, 2, 4
if (Test-CustomMap -MapIndexes $idxs) {
    Write-Host 'Continueing with script!'
} else {
    Write-Host 'Exitting...'
    exit 0
}

$idxs = 0, 1, 2, 4
if (Test-CustomMap -MapIndexes $idxs) {
    Write-Host 'Continueing with script!'
    Write-Host 'AGAIN!'
} else {
    Write-Host 'Exitting...'
    exit 0
}