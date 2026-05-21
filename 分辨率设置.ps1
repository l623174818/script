$csharpCode = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class DisplayManager
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool EnumDisplaySettings(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int ChangeDisplaySettings(ref DEVMODE lpDevMode, int dwFlags);

    const int ENUM_CURRENT_SETTINGS = -1;

    public class DisplayMode
    {
        public int Width { get; set; }
        public int Height { get; set; }
        public int Frequency { get; set; }
    }

    public static List<DisplayMode> GetAllModes()
    {
        var modes = new List<DisplayMode>();
        DEVMODE dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        int i = 0;
        while (EnumDisplaySettings(null, i, ref dm))
        {
            if (dm.dmBitsPerPel == 32)
            {
                modes.Add(new DisplayMode { Width = dm.dmPelsWidth, Height = dm.dmPelsHeight, Frequency = dm.dmDisplayFrequency });
            }
            i++;
            dm = new DEVMODE();
            dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        }
        return modes;
    }

    public static int SwitchMode(int width, int height, int frequency)
    {
        DEVMODE dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));

        int i = 0;
        while (EnumDisplaySettings(null, i, ref dm))
        {
            if (dm.dmBitsPerPel == 32 && dm.dmPelsWidth == width && dm.dmPelsHeight == height && dm.dmDisplayFrequency == frequency)
            {
                return ChangeDisplaySettings(ref dm, 0);
            }
            i++;
            dm = new DEVMODE();
            dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        }

        dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref dm);
        dm.dmPelsWidth = width;
        dm.dmPelsHeight = height;
        dm.dmDisplayFrequency = frequency;
        dm.dmBitsPerPel = 32;
        dm.dmFields = 0x00040000 | 0x00080000 | 0x00100000 | 0x00400000;
        return ChangeDisplaySettings(ref dm, 0);
    }

    public static DisplayMode GetCurrentMode()
    {
        DEVMODE dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        if (EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref dm))
        {
            return new DisplayMode { Width = dm.dmPelsWidth, Height = dm.dmPelsHeight, Frequency = dm.dmDisplayFrequency };
        }
        return null;
    }
}
'@

try
{
    Add-Type -TypeDefinition $csharpCode -ErrorAction Stop
}
catch
{
    Write-Host "  C# 编译失败: $($_.Exception.Message)"
    exit 1
}

function Build-DisplayList
{
    $allModes = [DisplayManager]::GetAllModes()
    $uniqueRes = $allModes | Group-Object { "$($_.Width)x$($_.Height)" } | ForEach-Object {
        $parts = $_.Name -split 'x'
        $w = [int]$parts[0]
        $h = [int]$parts[1]
        $bestFreq = ($_.Group | Sort-Object Frequency -Descending | Select-Object -First 1).Frequency
        [PSCustomObject]@{ Width = $w; Height = $h; Resolution = $_.Name; Frequency = $bestFreq }
    }
    return ($uniqueRes | Sort-Object Width -Descending)
}

$grouped = Build-DisplayList

$r = "$([char]27)[0m"
$g = "$([char]27)[92m"
$c = "$([char]27)[96m"
$b = "$([char]27)[1m"
$d = "$([char]27)[2m"

function Show-Table
{
    Clear-Host
    $current = [DisplayManager]::GetCurrentMode()
    if (-not $current) {
        $curRes = "未知"
        $curFreq = 0
    } else {
        $curRes = "$($current.Width)x$($current.Height)"
        $curFreq = $current.Frequency
    }

    Write-Host (" " + $b + $c + "╔══════════════════════════════════════════╗" + $r)
    Write-Host (" " + $b + $c + "║" + $r + $b + "  分辨率切换器  " + $g + $curRes + " @ " + $curFreq + "Hz" + $r + $b + $c + "        ║" + $r)
    Write-Host (" " + $b + $c + "╚══════════════════════════════════════════╝" + $r)
    Write-Host ""

    $maxResLen = ($grouped.Resolution | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
    if ($maxResLen -lt 10) { $maxResLen = 10 }

    Write-Host ("  " + $c + "序号" + $r + "  " + $c + "分辨率" + $r + " " * ($maxResLen - 4) + "  " + $c + "刷新率" + $r)

    $idx = 0
    foreach ($item in $grouped)
    {
        $idx++
        $idxStr = $idx.ToString().PadLeft(2) + "."
        $freqStr = "$($item.Frequency)Hz"
        $isCurrent = ($item.Resolution -eq $curRes -and $item.Frequency -eq $curFreq)

        if ($isCurrent) {
            Write-Host (" " + $b + $idxStr + $r + $g + "  " + $item.Resolution.PadRight($maxResLen) + "  " + $freqStr + "  ◀" + $r)
        } else {
            Write-Host (" " + $d + $idxStr + $r + "  " + $item.Resolution.PadRight($maxResLen) + "  " + $freqStr)
        }
    }

    Write-Host ""
    Write-Host (" " + $d + "输入序号  |  q 退出  |  r 刷新" + $r)
    Write-Host ""
}

do
{
    Show-Table
    $input = Read-Host "  > 输入序号"

    if ($input -eq 'q') { break }
    if ($input -eq 'r') { $grouped = Build-DisplayList; continue }

    $num = 0
    if (![int]::TryParse($input, [ref]$num))
    {
        Write-Host (" " + $d + "请输入数字" + $r)
        Start-Sleep -Milliseconds 800
        continue
    }

    if ($num -lt 1 -or $num -gt $grouped.Count)
    {
        Write-Host (" " + $d + "序号超出范围 (1-" + $grouped.Count + ")" + $r)
        Start-Sleep -Milliseconds 800
        continue
    }

    $target = $grouped[$num - 1]

    Write-Host (" " + $c + "→ " + $target.Resolution + " @ " + $target.Frequency + "Hz" + $r)
    $result = [DisplayManager]::SwitchMode($target.Width, $target.Height, $target.Frequency)

    if ($result -eq 0) {
        Write-Host (" " + $g + "✓ 切换成功" + $r)
    } elseif ($result -eq 1) {
        Write-Host (" " + $g + "✓ 切换成功 (需重启)" + $r)
    } else {
        Write-Host (" " + $r + "✗ 切换失败 ($result)" + $r + $b)
        Write-Host ""
        Read-Host "  按任意键退出"
        break
    }
} while ($true)