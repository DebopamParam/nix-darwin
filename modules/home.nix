{ ... }:

{
  imports = [
    ./home/packages.nix
    ./home/claude-profiles.nix
    ./home/shell.nix
    ./home/git.nix
    ./home/tmux.nix
    ./home/direnv.nix
  ];
}
