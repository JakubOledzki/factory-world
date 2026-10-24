using FactoryWorld.Modules.Abstractions;
using Microsoft.EntityFrameworkCore;

namespace FactoryWorld.Modules.Companies;

/// <summary>A company: players who run plots together and share a warehouse.</summary>
public sealed class CompanyRow
{
    public Guid Id { get; set; }

    public required string Name { get; set; }

    public required string NormalizedName { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
}

/// <summary>A player in a company; a player is in at most one.</summary>
public sealed class MemberRow
{
    public Guid AccountId { get; set; }

    public Guid CompanyId { get; set; }

    public required string Role { get; set; }

    public DateTimeOffset JoinedAt { get; set; }
}

/// <summary>An invitation the company's owner sent, until the player answers it.</summary>
public sealed class InviteRow
{
    public Guid CompanyId { get; set; }

    public Guid AccountId { get; set; }

    public DateTimeOffset InvitedAt { get; set; }
}

/// <summary>A plot its owner brought into their company.</summary>
public sealed class CompanyPlotRow
{
    public int X { get; set; }

    public int Y { get; set; }

    public Guid CompanyId { get; set; }

    public Guid OwnerId { get; set; }
}

/// <summary>How many of one item lie in a company's warehouse.</summary>
public sealed class WarehouseRow
{
    public Guid CompanyId { get; set; }

    public required string Item { get; set; }

    public long Quantity { get; set; }
}

/// <summary>Something that happened in a company, so members see who did what.</summary>
public sealed class LogRow
{
    public long Id { get; set; }

    public Guid CompanyId { get; set; }

    public DateTimeOffset At { get; set; }

    public Guid AccountId { get; set; }

    public required string Action { get; set; }

    public string? Item { get; set; }

    public long Quantity { get; set; }

    public Guid? Other { get; set; }
}

public sealed class CompaniesDbContext(DbContextOptions<CompaniesDbContext> options, GameDb gameDb) : ModuleDbContext(options, gameDb)
{
    public const string Schema = "companies";

    protected override void OnModelCreating(ModelBuilder model)
    {
        model.HasDefaultSchema(Schema);
        model.Entity<CompanyRow>(e =>
        {
            e.ToTable("companies");
            e.HasKey(c => c.Id);
            e.Property(c => c.Id).HasColumnName("id");
            e.Property(c => c.Name).HasColumnName("name").HasMaxLength(CompanyRules.MaxNameLength);
            e.Property(c => c.NormalizedName).HasColumnName("normalized_name").HasMaxLength(CompanyRules.MaxNameLength);
            e.Property(c => c.CreatedAt).HasColumnName("created_at");
            e.HasIndex(c => c.NormalizedName).IsUnique();
        });
        model.Entity<MemberRow>(e =>
        {
            e.ToTable("members");
            // One row per player: nobody is in two companies.
            e.HasKey(m => m.AccountId);
            e.Property(m => m.AccountId).HasColumnName("account_id");
            e.Property(m => m.CompanyId).HasColumnName("company_id");
            e.Property(m => m.Role).HasColumnName("role").HasMaxLength(16);
            e.Property(m => m.JoinedAt).HasColumnName("joined_at");
            e.HasIndex(m => m.CompanyId);
        });
        model.Entity<InviteRow>(e =>
        {
            e.ToTable("invites");
            e.HasKey(i => new { i.CompanyId, i.AccountId });
            e.Property(i => i.CompanyId).HasColumnName("company_id");
            e.Property(i => i.AccountId).HasColumnName("account_id");
            e.Property(i => i.InvitedAt).HasColumnName("invited_at");
            e.HasIndex(i => i.AccountId);
        });
        model.Entity<CompanyPlotRow>(e =>
        {
            e.ToTable("plots");
            // A plot is in one company at most.
            e.HasKey(p => new { p.X, p.Y });
            e.Property(p => p.X).HasColumnName("x");
            e.Property(p => p.Y).HasColumnName("y");
            e.Property(p => p.CompanyId).HasColumnName("company_id");
            e.Property(p => p.OwnerId).HasColumnName("owner_id");
            e.HasIndex(p => p.CompanyId);
        });
        model.Entity<WarehouseRow>(e =>
        {
            e.ToTable("warehouse", t => t.HasCheckConstraint("ck_warehouse_quantity", "quantity >= 0"));
            e.HasKey(w => new { w.CompanyId, w.Item });
            e.Property(w => w.CompanyId).HasColumnName("company_id");
            e.Property(w => w.Item).HasColumnName("item").HasMaxLength(64);
            e.Property(w => w.Quantity).HasColumnName("quantity");
        });
        model.Entity<LogRow>(e =>
        {
            e.ToTable("log");
            e.Property(l => l.Id).HasColumnName("id");
            e.Property(l => l.CompanyId).HasColumnName("company_id");
            e.Property(l => l.At).HasColumnName("at");
            e.Property(l => l.AccountId).HasColumnName("account_id");
            e.Property(l => l.Action).HasColumnName("action").HasMaxLength(16);
            e.Property(l => l.Item).HasColumnName("item").HasMaxLength(64);
            e.Property(l => l.Quantity).HasColumnName("quantity");
            e.Property(l => l.Other).HasColumnName("other");
            e.HasIndex(l => new { l.CompanyId, l.Id });
        });
    }
}
