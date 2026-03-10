using IIS_Site_Manager.API.Data;
using IIS_Site_Manager.API.Data.Entities;
using IIS_Site_Manager.API.Models;
using IIS_Site_Manager.API.Services;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

namespace IIS_Site_Manager.API;

public static class SecuritySmokeTests
{
    public static async Task<int> RunAsync()
    {
        try
        {
            TestPasswordHashingRoundTrip();
            TestAdminPasswordHashValidation();
            TestAdminJwtGeneration();
            TestAdminConfigurationValidation();
            await RunDatabaseBackedSmokeTestsAsync();

            Console.WriteLine("Security smoke tests passed.");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex);
            return 1;
        }
    }

    static async Task RunDatabaseBackedSmokeTestsAsync()
    {
        try
        {
            await TestCustomerRegistrationStoresOnlyHashAsync();
            await TestLegacyCustomerLoginMigratesPasswordAsync();
        }
        catch (SqlException ex) when (LooksLikeIntegratedSecurityEnvironmentIssue(ex))
        {
            Console.WriteLine($"Skipping database-backed smoke tests: {ex.Message}");
        }
    }

    static void TestPasswordHashingRoundTrip()
    {
        var hashing = new PasswordHashingService();
        var hash = hashing.HashPassword("Pa$$w0rd!");

        Assert(hash.StartsWith("pbkdf2-sha256$", StringComparison.Ordinal), "Password hash should use the PBKDF2 format.");
        Assert(hashing.VerifyPassword("Pa$$w0rd!", hash), "Password hash should validate the original password.");
        Assert(!hashing.VerifyPassword("wrong-password", hash), "Password hash should reject an invalid password.");
    }

    static void TestAdminPasswordHashValidation()
    {
        var hashing = new PasswordHashingService();
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Admin:Username"] = "admin",
                ["Admin:PasswordHash"] = hashing.HashPassword("SuperSecret!"),
                ["Admin:JwtKey"] = "12345678901234567890123456789012"
            })
            .Build();

        var auth = new AdminAuthService(config, hashing);

        Assert(auth.ValidateCredentials("admin", "SuperSecret!"), "Admin auth should accept the configured password hash.");
        Assert(auth.ValidateCredentials(" admin ", "SuperSecret!"), "Admin auth should trim the submitted username.");
        Assert(!auth.ValidateCredentials("admin", "bad"), "Admin auth should reject an invalid password.");
        Assert(!auth.ValidateCredentials("Admin", "SuperSecret!"), "Admin auth should keep username comparison case-sensitive.");
        Assert(!auth.ValidateCredentials("admin", string.Empty), "Admin auth should reject an empty password.");
    }

    static void TestAdminJwtGeneration()
    {
        var hashing = new PasswordHashingService();
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Admin:Username"] = "admin",
                ["Admin:PasswordHash"] = hashing.HashPassword("SuperSecret!"),
                ["Admin:JwtKey"] = "12345678901234567890123456789012",
                ["Admin:JwtIssuer"] = "TestIssuer",
                ["Admin:JwtAudience"] = "TestAudience",
                ["Admin:JwtExpiresMinutes"] = "15"
            })
            .Build();

        var auth = new AdminAuthService(config, hashing);
        var token = auth.GenerateToken("admin");

        var handler = new JwtSecurityTokenHandler();
        var parameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = "TestIssuer",
            ValidAudience = "TestAudience",
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(config["Admin:JwtKey"]!)),
            ClockSkew = TimeSpan.Zero
        };

        var principal = handler.ValidateToken(token, parameters, out var validatedToken);
        var jwt = (JwtSecurityToken)validatedToken;

        Assert(principal.Identity?.IsAuthenticated == true, "Generated admin JWT should validate successfully.");
        Assert(principal.FindFirstValue(ClaimTypes.Name) == "admin", "Generated admin JWT should carry the admin name.");
        Assert(principal.FindFirstValue(ClaimTypes.Role) == "admin", "Generated admin JWT should carry the admin role.");

        var expectedMinExpiry = DateTime.UtcNow.AddMinutes(14);
        var expectedMaxExpiry = DateTime.UtcNow.AddMinutes(16);
        Assert(jwt.ValidTo >= expectedMinExpiry && jwt.ValidTo <= expectedMaxExpiry, "Generated admin JWT should use the configured expiration window.");
    }

    static void TestAdminConfigurationValidation()
    {
        var valid = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Admin:Username"] = "admin",
                ["Admin:PasswordHash"] = "pbkdf2-sha256$100000$AAAAAAAAAAAAAAAAAAAAAA==$BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=",
                ["Admin:JwtKey"] = "12345678901234567890123456789012",
                ["ConnectionStrings:Default"] = "Server=localhost\\SQLEXPRESS;Database=Dummy;Trusted_Connection=True;TrustServerCertificate=True;Encrypt=False"
            })
            .Build();

        AdminSecurityConfiguration.Validate(valid);

        var shortJwtKey = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Admin:Username"] = "admin",
                ["Admin:PasswordHash"] = "pbkdf2-sha256$100000$AAAAAAAAAAAAAAAAAAAAAA==$BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=",
                ["Admin:JwtKey"] = "too-short",
                ["ConnectionStrings:Default"] = "Server=localhost\\SQLEXPRESS;Database=Dummy;Trusted_Connection=True;TrustServerCertificate=True;Encrypt=False"
            })
            .Build();

        var invalid = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Admin:Username"] = "admin",
                ["Admin:PasswordHash"] = "<set-admin-password-hash>",
                ["Admin:JwtKey"] = "<set-admin-jwt-key>",
                ["ConnectionStrings:Default"] = "<set-sqlserver-connection-string>"
            })
            .Build();

        AssertThrows<InvalidOperationException>(() => AdminSecurityConfiguration.Validate(shortJwtKey), "Short JWT keys should be rejected.");
        AssertThrows<InvalidOperationException>(() => AdminSecurityConfiguration.Validate(invalid), "Placeholder config should be rejected.");
    }

    static async Task TestCustomerRegistrationStoresOnlyHashAsync()
    {
        await using var scope = await TestDbScope.CreateAsync();
        var service = new HostingPlatformService(scope.Db, new PasswordHashingService());

        var result = service.RegisterCustomer(new RegisterCustomerRequest("user@example.com", "Pa$$w0rd!"));
        Assert(result.Success, "Customer registration should succeed.");

        var customer = await scope.Db.CustomerAccounts.SingleAsync(c => c.Email == "user@example.com");
        Assert(string.IsNullOrWhiteSpace(customer.Password), "New customers should not keep a plaintext password.");
        Assert(!string.IsNullOrWhiteSpace(customer.PasswordHash), "New customers should store a password hash.");
        Assert(customer.PasswordHashAlgorithm == "pbkdf2-sha256", "New customers should record the hash algorithm.");
    }

    static async Task TestLegacyCustomerLoginMigratesPasswordAsync()
    {
        await using var scope = await TestDbScope.CreateAsync();
        var passwordHashing = new PasswordHashingService();
        var customer = new CustomerAccountEntity
        {
            Id = Guid.NewGuid(),
            Email = "legacy@example.com",
            Password = "LegacyPass123!",
            PasswordHash = string.Empty,
            PasswordHashAlgorithm = string.Empty,
            Status = "active",
            CreatedUtc = DateTime.UtcNow
        };

        scope.Db.CustomerAccounts.Add(customer);
        await scope.Db.SaveChangesAsync();

        var service = new HostingPlatformService(scope.Db, passwordHashing);
        var result = service.Login(new LoginRequest("legacy@example.com", "LegacyPass123!"));

        Assert(result.Success, "Legacy customer login should succeed with the old plaintext password.");

        var updated = await scope.Db.CustomerAccounts.SingleAsync(c => c.Id == customer.Id);
        Assert(string.IsNullOrWhiteSpace(updated.Password), "Legacy plaintext password should be cleared after login.");
        Assert(!string.IsNullOrWhiteSpace(updated.PasswordHash), "Legacy login should write a password hash.");
        Assert(updated.PasswordHashAlgorithm == "pbkdf2-sha256", "Legacy login should record the hash algorithm.");
        Assert(passwordHashing.VerifyPassword("LegacyPass123!", updated.PasswordHash), "Migrated password hash should validate the original password.");
    }

    static void Assert(bool condition, string message)
    {
        if (!condition)
            throw new InvalidOperationException(message);
    }

    static void AssertThrows<TException>(Action action, string message) where TException : Exception
    {
        try
        {
            action();
        }
        catch (TException)
        {
            return;
        }

        throw new InvalidOperationException(message);
    }

    static bool LooksLikeIntegratedSecurityEnvironmentIssue(SqlException ex)
    {
        return ex.Message.Contains("Cannot generate SSPI context", StringComparison.OrdinalIgnoreCase) ||
               ex.Message.Contains("target principal name is incorrect", StringComparison.OrdinalIgnoreCase) ||
               ex.Message.Contains("login failed", StringComparison.OrdinalIgnoreCase);
    }

    sealed class TestDbScope : IAsyncDisposable
    {
        TestDbScope(ControlPlaneDbContext db)
        {
            Db = db;
        }

        public ControlPlaneDbContext Db { get; }

        public static async Task<TestDbScope> CreateAsync()
        {
            var builder = new DbContextOptionsBuilder<ControlPlaneDbContext>();
            builder.UseSqlServer(BuildConnectionString());

            var db = new ControlPlaneDbContext(builder.Options);
            await db.Database.MigrateAsync();
            return new TestDbScope(db);
        }

        public async ValueTask DisposeAsync()
        {
            try
            {
                await Db.Database.EnsureDeletedAsync();
            }
            finally
            {
                await Db.DisposeAsync();
            }
        }

        static string BuildConnectionString()
        {
            var databaseName = $"IISSiteManagerSecurityTests_{Guid.NewGuid():N}";
            var configured = Environment.GetEnvironmentVariable("SECURITY_TEST_SQL_CONNECTION");
            if (!string.IsNullOrWhiteSpace(configured))
            {
                var builder = new SqlConnectionStringBuilder(configured)
                {
                    InitialCatalog = databaseName
                };

                return builder.ConnectionString;
            }

            return $"Server=localhost\\SQLEXPRESS;Database={databaseName};Trusted_Connection=True;TrustServerCertificate=True;MultipleActiveResultSets=True;Encrypt=False";
        }
    }
}
