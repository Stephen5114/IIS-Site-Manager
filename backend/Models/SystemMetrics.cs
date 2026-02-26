namespace IIS_Site_Manager.API.Models;

public record SystemMetrics(
    double CpuUsagePercent,
    double MemoryUsagePercent,
    long MemoryUsedBytes,
    long MemoryTotalBytes,
    DateTime Timestamp
);
