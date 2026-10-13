namespace gamecontroller.Singletons
{
	/// <summary>
	/// Running match servers plus self-host settings.
	///
	/// Environment variables (all optional):
	///   SERVERBORN_PATH   Full path to Serverborn.exe (copy of Battleborn.exe with Reborn installed).
	///                     Default: Serverborn.exe in the current directory.
	///   GAME_PORT_START   First game port. Default 7777.
	///   GAME_PORT_COUNT   How many matches may run at once. Default 3.
	///   GC_PUBLIC_HOST    Address players are told to connect to (DuckDNS name, public IP or LAN IP).
	///                     Default: looked up once from checkip.amazonaws.com.
	///   GC_INTERNAL_URL   Address Serverborn uses to reach this coordinator. Default localhost:5000.
	/// </summary>
	public class GameSessions
	{
		public readonly object Lock = new object();

		public List<GameInstance> gameInstances = new List<GameInstance>();

		public readonly List<int> ports;

		public readonly string ServerbornPath;

		public readonly string InternalUrl;

		private string? _publicHost;

		public GameSessions()
		{
			int portStart = ReadInt("GAME_PORT_START", 7777);
			int portCount = Math.Max(ReadInt("GAME_PORT_COUNT", 3), 0);
			ports = Enumerable.Range(portStart, portCount).ToList();

			ServerbornPath = Environment.GetEnvironmentVariable("SERVERBORN_PATH") ?? "Serverborn.exe";
			InternalUrl = Environment.GetEnvironmentVariable("GC_INTERNAL_URL") ?? "localhost:5000";
			_publicHost = Environment.GetEnvironmentVariable("GC_PUBLIC_HOST");
		}

		/// <summary>Copy of the running instances, safe to iterate while cleanup or launches modify the list.</summary>
		public List<GameInstance> Snapshot()
		{
			lock (Lock)
			{
				return gameInstances.ToList();
			}
		}

		private static int ReadInt(string name, int fallback)
		{
			return int.TryParse(Environment.GetEnvironmentVariable(name), out int value) ? value : fallback;
		}

		public async Task<string> GetPublicHost()
		{
			if (string.IsNullOrWhiteSpace(_publicHost))
			{
				using HttpClient httpClient = new HttpClient();
				httpClient.Timeout = TimeSpan.FromSeconds(10);
				_publicHost = (await httpClient.GetStringAsync("https://checkip.amazonaws.com")).Trim();
			}

			return _publicHost;
		}
	}
}
