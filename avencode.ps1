[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline = $true)]
    [string[]]$Paths,

    [int]$CRFValue = 18,
    [int]$Preset = 4,
    [int]$VBoost = 2,
    [int]$SFilmGrain = 0,
    [int]$SFGDenoise = 0,
    [int[]]$CustomMap = $null, # Encouraged to use to exclude "core" tracks
    [string]$Start,
    [string]$Stop,
    [switch]$LiteralPath,
    [switch]$DeInterlace,
    [switch]$DIFramePreserve,
    [switch]$NoForceKeyFrames,
    [switch]$NoHWAccel,
    [switch]$VerifyOnly,
    [switch]$SkipVerify,
    [switch]$DryRun,
    [switch]$Help
)

begin {
    # Checks minimum PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Error 'PowerShell 7 or higher is required to run this script.'
        exit 1
    }
    
    if ($Help) {
        Get-Help $MyInvocation.MyCommand.Path
        exit 0
    }
    
    function Get-MKVPaths {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string[]]$Expressions,
            
            [bool]$LPath
        )
        
        $expanded_paths = @()
        
        foreach ($exp in $Expressions) {
            $res_errors = $null
            
            if ($LPath) {
                $resolved = Resolve-Path -LiteralPath $exp -ErrorVariable res_errors -ErrorAction SilentlyContinue
            }
            else {
                $resolved = Resolve-Path -Path $exp -ErrorVariable res_errors -ErrorAction SilentlyContinue
            }
    
            $resolved | ForEach-Object {
                $path = $_.ProviderPath
                if ((Test-Path -PathType Leaf -LiteralPath $path) -and ($path -like '*.mkv')) {
                    $expanded_paths += $path
                }
                else {
                    Write-Warning "Skipping '$path': Not a valid .mkv file."
                }
            }
    
            if ($res_errors) {
                Write-Warning "Could not resolve path '$exp'. Skipping..."
            }
        }
        
        return $expanded_paths
    }
    
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
    
    function Get-MKVStreams {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$MKVFile
        )
        
        $streamJson = & ffprobe -v error -show_streams -print_format json $MKVFile 2>$null | ConvertFrom-Json
        
        if (-not $streamJson -or -not $streamJson.streams) {
            Write-Warning "Could not retrieve stream information for '$MKVFile'"
            return $null
        }
        
        return $streamJson.streams
    }
    
    function Get-OutPath {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$File
        )
        return $File -replace '\.mkv$', '-reenc.mkv'
    }
    
    function New-MKVConfig {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$File,
            
            [scriptblock]$OutPathFunc = { param ($f) Get-OutPath $f },
            [scriptblock]$StreamExtractor = { param ($s) Get-MKVStreams $s }
        )
        
        $output = &$OutPathFunc $File
        $streams = &$StreamExtractor $File
    
        return [PSCustomObject]@{
            Input   = $File
            Output  = $output
            Streams = $streams
        }
    }
    
    function Get-ToFlac {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [object[]]$StreamJson
        )
    
        # Only codecs that can safely be converted to flac.
        # Spatial audio like Dolby Atmos cannot.
        $lossless_codecs = @('truehd', 'dts', 'pcm_s16be', 'pcm_s24be', 'pcm_s16le', 'pcm_s24le', 'pcm_bluray')
        
        if ($StreamJson.codec_name -in $lossless_codecs) {
            if (($StreamJson.codec_name -eq 'dts') -and ($StreamJson.profile -ne 'DTS-HD MA')) {
                return $false
            }
            return $true
        }
        return $false
    }
    
    function Get-TotalSize {
        param($filePaths)
        
        $existing = $filePaths | Where-Object { Test-Path $_ }
        if (-not $existing) { return 0 }
        
        return (Get-Item -LiteralPath $existing | Measure-Object -Property Length -Sum).Sum
    }
    
    # Function from https://claytonerrington.com/blog/human-readable-file-sizes-in-power-shell/
    function ConvertTo-HumanReadable {
        param([double]$bytecount)
        
        if ($bytecount -le 0) { return "0 Bytes" }
        
        switch -Regex ([math]::truncate([math]::log($bytecount, 1024))) {
            '^0' { "$bytecount Bytes" }
            '^1' { "{0:n2} KB" -f ($bytecount / 1KB) }    
            '^2' { "{0:n2} MB" -f ($bytecount / 1MB) }
            '^3' { "{0:n2} GB" -f ($bytecount / 1GB) }
            '^4' { "{0:n2} TB" -f ($bytecount / 1TB) }
            default { "{0:n2} TB" -f ($bytecount / 1TB) }
        }
    }
    
    function Get-Mappings {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [object[]]$Streams,
            [int[]]$CustomMap,
            [scriptblock]$FlacPredicate = { param($s) Get-ToFlac $s }
        )
        
        $outIndex = 0
        $mappings = foreach ($stream in $Streams) {
            $ctype = $stream.codec_type
            $index = $stream.index
    
            if ($CustomMap -and $index -notin $CustomMap) {
                continue
            }
    
            switch ($ctype) {
                'audio' {
                    '-map'; "0:$index"; "-c:$outIndex"
                    if (&$FlacPredicate $stream) { 'flac' } else { 'copy' }
                    $outIndex++
                }
                'video' {
                    '-map'; "0:$index"; "-c:$outIndex"; 'libsvtav1'
                    $outIndex++
                }
                'subtitle' {
                    '-map'; "0:$index"; "-c:$outIndex"; 'copy'
                    $outIndex++
                }
            }
        }
    
        return $mappings
    }
    
    function Invoke-Encoding {
        param(
            [Parameter(Mandatory)]
            $mkvFile
        )
    
        $trim_times = @(
            if (-not [string]::IsNullOrWhiteSpace($Start)) { '-ss', $Start }
            if (-not [string]::IsNullOrWhiteSpace($Stop)) { '-to', $Stop }
        )
    
        $maps = Get-Mappings -Streams $mkvFile.Streams -CustomMap $CustomMap
    
        $svtList = [System.Collections.Generic.List[string]]::new()
        $svtList.Add("preset=$Preset")
        $svtList.Add('enable-tf=0')
        $svtList.Add('enable-qm=1')
        $svtList.Add('qm-min=0')
        $svtList.Add('tune=0')
        $svtList.Add('enable-variance-boost=1')
        $svtList.Add("variance-boost-strength=$VBoost")
    
        if ($SFilmGrain) {
            $svtList.Add("film-grain=$SFilmGrain")
            $svtList.Add("film-grain-denoise=$SFGDenoise")
        }
        $svtParams = $svtList -join ':'
    
        $ffmpegArgs = @(
            '-map', '0:t?'
    
            if ($DeInterlace -or $DIFramePreserve) {
                $mode = if ($DIFramePreserve) { 'send_frame' } else { 'send_field' }
                '-vf', "bwdif=mode=$mode"
            }
            
            if ((-not $NoForceKeyFrames)) {
                '-force_key_frames', 'chapters'
            }
            
            '-crf', $CRFValue
            '-pix_fmt', 'yuv420p10le'
            '-svtav1-params', $svtParams
            
            '-disposition:s', '0'
            '-map_metadata', '0'
            '-map_chapters', '0'
        )
    
        $metadata = "CRF: $CRFValue, SVTAV1 Params: $svtParams"
    
        if ($DryRun) {
            Write-Host "ffmpeg $($trim_times -join ' ') -i '$($mkvFile.Input)' $($maps -join ' ') $($ffmpegArgs -join ' ') -metadata ENCODER_SETTINGS=""$metadata"" '$($mkvFile.Output)'"`n
        }
        else {
            & ffmpeg -hide_banner @trim_times -i $mkvFile.Input @maps @ffmpegArgs -metadata ENCODER_SETTINGS=$metadata $mkvFile.Output
        }
    }
    
    function Get-AvailableHWAccel {
        $gpus = (Get-CimInstance Win32_VideoController).Name
        
        if ($gpus -match 'NVIDIA') { return 'cuda' }
        elseif ($gpus -match 'Intel') { return 'qsv' }
        else { return 'd3d11va' }
    }
    
    function Test-Output {
        param(
            [Parameter(Mandatory)]
            $mkvFile
        )
        
        $out = $mkvFile.Output
        $errorLog = "${out}_errors.log"
        
        Write-Host "Checking '${out}'..." -NoNewline
        
        $ffargs = @(
            '-v', 'error'
    
            if (-not $NoHWAccel) {
                '-hwaccel', (Get-AvailableHWAccel)
            }
            
            '-i', $out
            '-map', '0:v?'
            '-f', 'null', '-'
        )
        
        & ffmpeg -hide_banner @ffargs 2> $errorLog
        
        if ((Test-Path $errorLog) -and ((Get-Item $errorLog).Length -gt 0)) {
            Write-Host ' [ERROR]' -ForegroundColor Red
            return $false
        }
        else {
            Write-Host ' [OK]' -ForegroundColor Green
            if (Test-Path $errorLog) { Remove-Item $errorLog }
            return $true
        }
    }

    ################ SCRIPT START ####################

    if ($CustomMap -and (-not (Test-CustomMap $CustomMap))) {
        Write-Host 'Exiting...'
        exit 0
    }
    $allFilesToProcess = @()
    $failedFiles = 0

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
}

process {

    $filesToProcess = Get-MKVPaths -Expressions $Paths -LPath $LiteralPath
    $allFilesToProcess += $filesToProcess


    foreach ($f in $filesToProcess) {
        $mkvFile = New-MKVConfig $f
    
        if ($VerifyOnly) {
            $mkvFile.Output = $mkvFile.Input
        }
        else {
            Invoke-Encoding $mkvFile
        }
    
        if ((-not $DryRun) -and (-not $SkipVerify)) {
            $pass = Test-Output $mkvFile
            if (-not $pass) { $failedFiles++ }
        }
    }
}

end {
    $outputFiles = $allFilesToProcess | ForEach-Object { Get-OutPath $_ }

    $inputSize = Get-TotalSize $allFilesToProcess
    $outputSize = Get-TotalSize $outputFiles
    $difference = $inputSize - $outputSize

    $diffPercent = if ($inputSize -gt 0) {
        [Math]::Floor(($difference / $inputSize) * 100)
    }
    else { 0 }

    $timer.Stop()

    Write-Host ""
    Write-Host "==================================="
    Write-Host "Files processed : $($allFilesToProcess.Count)"
    Write-Host "Failed tests    : $failedFiles"
    Write-Host "Input size      : $(ConvertTo-HumanReadable $inputSize)"
    Write-Host "Output size     : $(ConvertTo-HumanReadable $outputSize)"
    Write-Host "Space saved     : $(ConvertTo-HumanReadable $difference) ($diffPercent%)"
    Write-Host ("Elapsed time    : {0:hh\:mm\:ss}" -f $timer.Elapsed)
    Write-Host "==================================="

}

