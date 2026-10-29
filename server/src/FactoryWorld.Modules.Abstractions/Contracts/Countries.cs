using System.Security.Cryptography;
using System.Text;

namespace FactoryWorld.Modules.Abstractions.Contracts;

/// <summary>The offices of a country's government. A president holds every power; each minister one area.</summary>
public static class CountryOffices
{
    public const string President = "president";

    /// <summary>Taxes, the fee foreigners pay for plots, tariffs, the housing programme.</summary>
    public const string Finance = "finance";

    /// <summary>Subsidies for goods delivered to towns.</summary>
    public const string Industry = "industry";

    /// <summary>The national railway.</summary>
    public const string Transport = "transport";

    /// <summary>Alliances and embargoes.</summary>
    public const string Foreign = "foreign";

    /// <summary>The police (Law module).</summary>
    public const string Interior = "interior";

    /// <summary>The courts (Law module); without one the president judges.</summary>
    public const string Justice = "justice";

    /// <summary>The ministries a president fills.</summary>
    public static readonly IReadOnlyList<string> Ministries = [Finance, Industry, Transport, Foreign, Interior, Justice];
}

/// <summary>What country <c>to</c> charges on goods from country <c>from</c>: whether it lets them in at all, and the tariff in percent
/// of their worth, generally and for single items (which take the place of the general one).</summary>
public sealed record CountryTrade(bool Embargo, int TariffPercent, IReadOnlyDictionary<string, int> ItemTariffPercent);

/// <summary>Countries as their governments run them, for modules that enforce their laws (the police collects tariffs at the border).
/// Country codes are Natural Earth's ADM0_A3, such as "POL".</summary>
public interface ICountries
{
    /// <summary>The country the plot lies in, or null (the sea, lakes, Antarctica).</summary>
    Task<string?> CountryOfPlotAsync(int x, int y, CancellationToken cancellationToken);

    /// <summary>The player's country, or null when they chose none.</summary>
    Task<string?> CitizenshipAsync(Guid player, CancellationToken cancellationToken);

    /// <summary>The offices the player holds in the country's government this term (<see cref="CountryOffices"/>).</summary>
    Task<IReadOnlySet<string>> OfficesAsync(Guid player, string country, CancellationToken cancellationToken);

    /// <summary>The <see cref="IWallet"/> account of the country's treasury, or null while the country has no government (no president).</summary>
    Task<Guid?> TreasuryAsync(string country, CancellationToken cancellationToken);

    /// <summary>What <paramref name="to"/> charges on goods coming from <paramref name="from"/>.</summary>
    Task<CountryTrade> TradeAsync(string from, string to, CancellationToken cancellationToken);
}

public static class CountryTreasury
{
    /// <summary>The wallet account of a country's treasury: the same id for the same code, never a player's.</summary>
    public static Guid Account(string country)
    {
        var hash = MD5.HashData(Encoding.UTF8.GetBytes("factory-world/treasury/" + country));
        hash[6] = (byte)((hash[6] & 0x0f) | 0x30);
        hash[8] = (byte)((hash[8] & 0x3f) | 0x80);
        return new Guid(hash, bigEndian: true);
    }
}
