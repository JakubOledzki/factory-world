using System.Diagnostics;
using System.Globalization;
using System.Text;
using FactoryWorld.Modules.Abstractions;

namespace FactoryWorld.Server;

/// <summary>
/// <c>/metrics</c> in the Prometheus text format, for Grafana Alloy (deploy/alloy) to scrape: how many messages of
/// each kind the server answered and how long they took, who is online, what the factories made and where money went
/// (<see cref="GameCounters"/>) and what the process uses. Only containers in the compose network reach it; Caddy
/// forwards just <c>/ws</c> and <c>/health</c> to the internet.
/// </summary>
public static class MetricsEndpoint
{
    public static IResult Handle(ServerLoad load, OnlinePlayers online, GameCounters counters)
    {
        var text = new StringBuilder();

        Header(text, "factoryworld_message_duration_seconds", "histogram",
            "Time spent answering a message, by kind; bot messages start with \"bot \".");
        foreach (var total in load.Totals())
        {
            var type = Escape(total.Type);
            for (var i = 0; i < ServerLoad.Buckets.Length; i++)
            {
                text.Append("factoryworld_message_duration_seconds_bucket{type=\"").Append(type).Append("\",le=\"")
                    .Append(Number(ServerLoad.Buckets[i])).Append("\"} ").Append(total.InBucket[i]).Append('\n');
            }

            text.Append("factoryworld_message_duration_seconds_bucket{type=\"").Append(type).Append("\",le=\"+Inf\"} ")
                .Append(total.Count).Append('\n');
            text.Append("factoryworld_message_duration_seconds_sum{type=\"").Append(type).Append("\"} ")
                .Append(Number(total.Seconds)).Append('\n');
            text.Append("factoryworld_message_duration_seconds_count{type=\"").Append(type).Append("\"} ")
                .Append(total.Count).Append('\n');
        }

        Gauge(text, "factoryworld_players_online", "Accounts playing on a connection right now.", online.Players);
        Gauge(text, "factoryworld_bots_online", "Bots in a play session right now.", online.Bots);

        var items = counters.Items();
        Header(text, "factoryworld_items_produced_total", "counter",
            "Pieces of an item made by machines, the workbench and gathering on plots, by players or bots.");
        foreach (var item in items)
        {
            Labelled(text, "factoryworld_items_produced_total", item.Item, item.Bot, "item", item.Produced);
        }

        Header(text, "factoryworld_items_consumed_total", "counter", "Pieces of an item used up the same way.");
        foreach (var item in items)
        {
            Labelled(text, "factoryworld_items_consumed_total", item.Item, item.Bot, "item", item.Consumed);
        }

        var money = counters.MoneyTotals();
        Header(text, "factoryworld_money_in_cents_total", "counter",
            "Cents paid to players' wallets, by kind of ledger reason (its first word).");
        foreach (var total in money)
        {
            Labelled(text, "factoryworld_money_in_cents_total", total.Reason, total.Bot, "reason", total.InCents);
        }

        Header(text, "factoryworld_money_out_cents_total", "counter", "Cents taken from players' wallets, the same way.");
        foreach (var total in money)
        {
            Labelled(text, "factoryworld_money_out_cents_total", total.Reason, total.Bot, "reason", total.OutCents);
        }

        using var process = Process.GetCurrentProcess();
        Header(text, "process_cpu_seconds_total", "counter", "Processor time used by the server.");
        text.Append("process_cpu_seconds_total ").Append(Number(process.TotalProcessorTime.TotalSeconds)).Append('\n');
        Gauge(text, "process_resident_memory_bytes", "Memory the server process holds.", process.WorkingSet64);
        Gauge(text, "dotnet_gc_heap_bytes", "Managed heap size.", GC.GetTotalMemory(false));
        Gauge(text, "dotnet_threadpool_queue_length", "Work items waiting for a thread pool thread.",
            ThreadPool.PendingWorkItemCount);
        Gauge(text, "dotnet_threadpool_threads", "Thread pool threads.", ThreadPool.ThreadCount);

        return Results.Text(text.ToString(), "text/plain; version=0.0.4; charset=utf-8");
    }

    private static void Header(StringBuilder text, string name, string kind, string help) =>
        text.Append("# HELP ").Append(name).Append(' ').Append(help).Append("\n# TYPE ").Append(name).Append(' ')
            .Append(kind).Append('\n');

    private static void Labelled(StringBuilder text, string name, string value, bool bot, string label, long count) =>
        text.Append(name).Append('{').Append(label).Append("=\"").Append(Escape(value)).Append("\",who=\"")
            .Append(GameCounters.Who(bot)).Append("\"} ").Append(count).Append('\n');

    private static void Gauge(StringBuilder text, string name, string help, long value)
    {
        Header(text, name, "gauge", help);
        text.Append(name).Append(' ').Append(value).Append('\n');
    }

    private static string Number(double value) => value.ToString("R", CultureInfo.InvariantCulture);

    private static string Escape(string value) => value.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\n", "\\n");
}
