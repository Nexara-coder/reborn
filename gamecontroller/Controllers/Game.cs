using Microsoft.AspNetCore.Mvc;
using gamecontroller.Middleware;
using System.Diagnostics;
using gamecontroller.Singletons;

namespace gamecontroller.Controllers
{
    [ApiController]
    [Route("api/games")]
    public class Game : ControllerBase
    {
        private readonly RCONAuth _RCONAuth;

        private readonly ILogger<Game> _logger;

        private readonly GameSessions _gameSessions;

        public Game(ILogger<Game> logger, GameSessions sessions)
        {
            _logger = logger;
            _RCONAuth = new RCONAuth();
            _gameSessions = sessions;
        }

        // Caller must hold _gameSessions.Lock.
        private int? GetFreePort()
        {
            HashSet<int> inUse = _gameSessions.gameInstances.Select(instance => instance.ServerConfig.Port).ToHashSet();

            foreach (int port in _gameSessions.ports)
            {
                if (!inUse.Contains(port))
                {
                    return port;
                }
            }

            return null;
        }

        [HttpGet]
        public List<GameInstance> Get()
        {
            return _gameSessions.Snapshot();
        }

        // Creating a match requires "Authorization: Bearer <RCON_TOKEN>" (the "RCON Password" box in the overlay).
        [HttpPost]
        public async Task<bool> Post([FromBody] GameCreationConfig config)
        {
            if (!await _RCONAuth.HasValidRCONAuth(HttpContext))
            {
                HttpContext.Response.StatusCode = 401;
                return false;
            }

            string publicHost = await _gameSessions.GetPublicHost();

            GameInstance instance;

            lock (_gameSessions.Lock)
            {
                int? port = GetFreePort();

                if (!port.HasValue)
                {
                    _logger.LogWarning("No free game ports; raise GAME_PORT_COUNT to allow more concurrent matches.");
                    HttpContext.Response.StatusCode = 503;
                    return false;
                }

                instance = new GameInstance(config, publicHost, port.Value);

                // Reserve the port before the process starts so a second request can't take it.
                _gameSessions.gameInstances.Add(instance);
            }

            try
            {
                string fullPath = Path.GetFullPath(_gameSessions.ServerbornPath);

                // Argument order matters: Init::ServerConfig reads argv[3]=="GameCoordinator", argv[4]=coordinator, argv[5]=server token.
                var startInfo = new ProcessStartInfo(fullPath,
                    "-SEEKFREEPACKAGEMAP -SEEKFREELOADINGPCCONSOLE GameCoordinator " + _gameSessions.InternalUrl + " " + instance.ServerAuthToken)
                {
                    WorkingDirectory = Path.GetDirectoryName(fullPath) ?? Directory.GetCurrentDirectory(),
                    UseShellExecute = false
                };

                Process? proc = Process.Start(startInfo);

                if (proc == null)
                {
                    throw new InvalidOperationException("Process.Start returned null");
                }

                instance.PID = proc.Id;

                _logger.LogInformation("Started Serverborn PID {Pid} on port {Port} for \"{Name}\"", proc.Id, instance.ServerConfig.Port, instance.InstanceName);

                return true;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to start Serverborn at {Path}. Check SERVERBORN_PATH.", _gameSessions.ServerbornPath);

                lock (_gameSessions.Lock)
                {
                    _gameSessions.gameInstances.Remove(instance);
                }

                HttpContext.Response.StatusCode = 500;
                return false;
            }
        }

        [HttpGet("server-config")]
        public ServerConfig? GetServerConfig()
        {
            if (HttpContext.Request.Headers.TryGetValue("X-Server-Token", out var authHeader))
            {
                foreach (GameInstance instance in _gameSessions.Snapshot())
                {
                    if (instance.ServerAuthToken == authHeader.ToString())
                    {
                        return instance.ServerConfig;
                    }
                }
            }

            HttpContext.Response.StatusCode = 401;
            return null;
        }

        [HttpPost("server-poll")]
        public void PostServerPoll([FromBody] ServerPollUpdate update)
        {
            if (HttpContext.Request.Headers.TryGetValue("X-Server-Token", out var authHeader))
            {
                foreach (GameInstance instance in _gameSessions.Snapshot())
                {
                    if (instance.ServerAuthToken == authHeader.ToString())
                    {
                        instance.CurrentNumPlayers = update.ConnectedPlayers;
                        instance.LastUpdateTime = DateTime.UtcNow;
                        instance.MatchStarted = update.HumansHaveStarted;

                        HttpContext.Response.StatusCode = 200;
                        return;
                    }
                }
            }

            HttpContext.Response.StatusCode = 401;
        }
    }
}
