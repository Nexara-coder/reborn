using gamecontroller;
using gamecontroller.Singletons;
using Microsoft.Extensions.Hosting;
using System.Diagnostics;

/// <summary>
/// Frees ports held by servers that have exited, hung, or never finished starting,
/// and kills hung Serverborn processes so they don't pile up on the host.
/// </summary>
public class SessionCleanupService : BackgroundService
{
	// A running server polls every few seconds; this long without one means it's hung or gone.
	private static readonly TimeSpan PollTimeout = TimeSpan.FromSeconds(30);

	// Time a new server gets to load the map and send its first poll.
	private static readonly TimeSpan StartupTimeout = TimeSpan.FromMinutes(5);

	private readonly ILogger<SessionCleanupService> _logger;
	private readonly GameSessions _gameSessions;

	public SessionCleanupService(ILogger<SessionCleanupService> logger, GameSessions gameSessions)
	{
		_logger = logger;
		_gameSessions = gameSessions;
	}

	protected override async Task ExecuteAsync(CancellationToken stoppingToken)
	{
		while (!stoppingToken.IsCancellationRequested)
		{
			try
			{
				CleanupSessions();
			}
			catch (Exception ex)
			{
				_logger.LogError(ex, "Session cleanup failed");
			}

			await Task.Delay(5000, stoppingToken);
		}
	}

	private static bool HasExited(GameInstance instance)
	{
		if (!instance.PID.HasValue)
		{
			return false; // still starting
		}

		try
		{
			using Process process = Process.GetProcessById(instance.PID.Value);
			return process.HasExited;
		}
		catch (ArgumentException)
		{
			return true; // no such process
		}
		catch (InvalidOperationException)
		{
			return true; // process object no longer valid
		}
	}

	private void KillQuietly(GameInstance instance)
	{
		if (!instance.PID.HasValue)
		{
			return;
		}

		try
		{
			using Process process = Process.GetProcessById(instance.PID.Value);
			if (!process.HasExited)
			{
				process.Kill(entireProcessTree: true);
				_logger.LogWarning("Killed unresponsive Serverborn PID {Pid} (\"{Name}\")", instance.PID, instance.InstanceName);
			}
		}
		catch (Exception)
		{
			// Already gone.
		}
	}

	private void CleanupSessions()
	{
		DateTime now = DateTime.UtcNow;
		List<GameInstance> toRemove = new List<GameInstance>();

		foreach (GameInstance instance in _gameSessions.Snapshot())
		{
			bool exited = HasExited(instance);
			bool hung = instance.LastUpdateTime.HasValue && now - instance.LastUpdateTime.Value > PollTimeout;
			bool neverStarted = !instance.LastUpdateTime.HasValue && now - instance.CreatedAt > StartupTimeout;

			if (exited || hung || neverStarted)
			{
				if (!exited)
				{
					KillQuietly(instance);
				}

				_logger.LogInformation("Freeing port {Port} from \"{Name}\" (exited={Exited}, hung={Hung}, neverStarted={NeverStarted})",
					instance.ServerConfig.Port, instance.InstanceName, exited, hung, neverStarted);

				toRemove.Add(instance);
			}
		}

		if (toRemove.Count > 0)
		{
			lock (_gameSessions.Lock)
			{
				_gameSessions.gameInstances.RemoveAll(toRemove.Contains);
			}
		}
	}
}
