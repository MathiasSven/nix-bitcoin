# This file is generated by ../helper/update-flake.nix
pkgs: pkgsUnstable:
{
  inherit (pkgs)
    btcpayserver
    charge-lnd
    # fulcrum
    # hwi
    # lightning-loop
    lightning-pool
    lndconnect;
    # nbxplorer;

  inherit (pkgsUnstable)
    bitcoin
    bitcoind
    clboss
    clightning
    electrs
    elementsd
    extra-container
    fulcrum
    hwi
    lightning-loop
    lnd
    lndhub-go
    nbxplorer;

  inherit pkgs pkgsUnstable;
}
