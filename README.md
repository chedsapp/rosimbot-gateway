# RoSimBot Gateway
Establishes gateway and forwards messages to the cloudflare worker

My server is running on nixos, so this ends up being a systemd service
This should go into your configuration.nix:
```nix
systemd.services.rosimbot-gateway = {
  description = "rosimbot Discord gateway";
  wantedBy = [ "multi-user.target" ];
  wants = [ "network-online.target" ];
  after = [ "network-online.target" ];
  serviceConfig = {
    ExecStart = "/usr/local/bin/rosimbot-gateway";
    EnvironmentFile = "/etc/rosimbot-gateway.env";
    Restart = "on-failure";
    RestartSec = 5;
    KillSignal = "SIGINT";
    TimeoutStopSec = 10;
    DynamicUser = true;
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
  };
};
```
