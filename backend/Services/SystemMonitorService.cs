using System.Diagnostics;
using System.Runtime.InteropServices;

namespace IIS_Site_Manager.API.Services;

public class SystemMonitorService
{
    static PerformanceCounter? _cpuCounter;

    public SystemMonitorService()
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            try
            {
                _cpuCounter = new PerformanceCounter("Processor", "% Processor Time", "_Total");
                _cpuCounter.NextValue(); // First call returns 0
            }
            catch { /* Ignore if not admin */ }
        }
    }

    public (double CpuPercent, double MemoryPercent, long MemoryUsed, long MemoryTotal) GetMetrics()
    {
        var memory = GetMemoryMetrics();
        var cpu = GetCpuUsage();
        return (cpu, memory.percent, memory.used, memory.total);
    }

    (double percent, long used, long total) GetMemoryMetrics()
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            var memStatus = new MEMORYSTATUSEX();
            memStatus.dwLength = (uint)Marshal.SizeOf(memStatus);
            if (GlobalMemoryStatusEx(ref memStatus))
            {
                var total = (long)memStatus.ullTotalPhys;
                var used = total - (long)memStatus.ullAvailPhys;
                var percent = total > 0 ? (double)used / total * 100 : 0;
                return (percent, used, total);
            }
        }

        return (0, 0, 0);
    }

    double GetCpuUsage()
    {
        try
        {
            if (_cpuCounter != null)
            {
                var value = _cpuCounter.NextValue();
                return Math.Round(value, 2);
            }
        }
        catch { }
        return 0;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct MEMORYSTATUSEX
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);
}
