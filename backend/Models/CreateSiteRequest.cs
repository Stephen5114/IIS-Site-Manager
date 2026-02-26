namespace IIS_Site_Manager.API.Models;

public record CreateSiteRequest(
    string SiteName,
    string Domain,
    string PhysicalPath,
    string AppPoolName = "DefaultAppPool",
    int Port = 80
);
