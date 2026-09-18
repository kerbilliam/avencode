# avencode

`avencode` is an automated PowerShell batch script designed to re-encode `.mkv` video files into **AV1** (`libsvtav1`), convert lossless audio tracks to **FLAC**, and verify output file integrity.

---

## Features

* **AV1 Encoding**: Encodes video streams to 10-bit AV1 using `libsvtav1`.
* **Smart Audio Mapping**: Retains multi-channel layouts while automatically converting uncompressed or spatial-free lossless formats (TrueHD, DTS-HD MA, PCM) to FLAC.
* **Key Frames at Chapter Start Times**: Configures ffmpeg to force key frames at chapter start times for frame perfect chapter skipping and episode splitting.
* **Integrity Verification**: Decodes encoded outputs to `null` post-encoding using hardware acceleration (`CUDA`, `QSV`, or `D3D11VA`) to detect stream errors.
* **Batch Processing & Pipeline Support**: Supports direct file paths, wildcard patterns, and pipeline input.
* **Dry Run Mode**: Prints generated `ffmpeg` execution strings without encoding.

---

## Prerequisites

* **PowerShell 7.0+**
* **FFmpeg** and **FFprobe** installed and accessible in your system's `PATH`.

---

## Parameters

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `-Paths` | `string[]` | *None* | Target `.mkv` files or wildcard expressions. Accepts pipeline input. |
| `-CRFValue` | `int` | `18` | Constant Rate Factor (quality setting) for `libsvtav1`. |
| `-Preset` | `int` | `4` | SVT-AV1 encoding preset speed (0–13). |
| `-VBoost` | `int` | `2` | Variance boost strength for SVT-AV1. |
| `-SFilmGrain` | `int` | `0` | SVT-AV1 synthetic film grain amount. |
| `-SFGDenoise` | `int` | `0` | Film grain denoise option (0 or 1). |
| `-CustomMap` | `int[]` | `null` | Selective stream indices to include (e.g., `-CustomMap 0,1,2`). |
| `-Start` | `string` | `null` | Trim start timestamp (e.g., `"00:01:30"`). |
| `-Stop` | `string` | `null` | Trim end timestamp (e.g., `"00:45:00"`). |
| `-LiteralPath` | `string` | `null` | Explicit path resolution without wildcard evaluation. |
| `-DeInterlace` | `switch` | `false` | Enables `bwdif` deinterlacing (`send_field` mode). |
| `-DIFramePreserve` | `switch` | `false` | Enables `bwdif` deinterlacing with `send_frame` mode. |
| `-NoForceKeyFrames` | `switch` | `false` | Disables keyframe placement at chapter markers. |
| `-NoHWAccel` | `switch` | `false` | Disables hardware acceleration during post-encode verification. |
| `-VerifyOnly` | `switch` | `false` | Skips encoding and only runs integrity verification on target files. |
| `-SkipVerify` | `switch` | `false` | Encodes files without performing post-encode verification. |
| `-DryRun` | `switch` | `false` | Displays calculated `ffmpeg` commands without executing them. |

---

## Usage Examples

**Basic Encoding**

```powershell
.\avencode.ps1 -Paths "C:\Media\Movie.mkv"
```

**Filenames with Regex/Wildcard Characters**

```powershell
.\avencode.ps1 -LiteralPath -Paths "Show A [Part 1].mkv"
```

**Batch Processing via Pipeline**

```powershell
Get-Content "vids_to_encode.txt" | .\avencode.ps1 -Preset 5 -CRFValue 20 -LiteralPath
```

**Custom Mapping & Film Grain Synthesis**

```powershell
.\avencode.ps1 -Paths "Input.mkv" -CustomMap 0,1 -SFilmGrain 8 -SFGDenoise 1
```

**Dry Run Command Preview**

```powershell
.\avencode.ps1 -Paths "Test.mkv" -DryRun
```

## Bash version planned...