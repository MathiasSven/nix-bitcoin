{ config, pkgs, lib, ... }:

# Workflow for releasing a new nix-bitcoin version with incompatible changes:
# Let V be the version of the upcoming, incompatible release.
# 1. Add change descriptions with `version = V` at the end of the `changes` list below.
# 2. Set `nix-bitcoin.configVersion = V` in ../examples/configuration.nix.

with lib;
let
  options = {
    nix-bitcoin.configVersion = mkOption {
      type = with types; nullOr str;
      default = null;
      description = mdDoc ''
        Set this option to the nix-bitcoin release version that your config is
        compatible with.

        When upgrading to a backwards-incompatible release, nix-bitcoin will throw an
        error during evaluation and provide instructions for migrating your config to
        the new release.
      '';
    };
  };

  # Sorted by increasing version numbers
  changes = [
    {
      version = "0.0.26";
      condition = config.services.joinmarket.enable;
      message = let
        inherit (config.services.joinmarket) dataDir;
      in ''
        JoinMarket 0.8.0 moves from wrapped segwit wallets to native segwit wallets.

        If you have an existing wrapped segwit wallet, you have to manually migrate
        your funds to a new native segwit wallet.

        To migrate, you first have to deploy the new JoinMarket version:
        1. Set `nix-bitcoin.configVersion = "0.0.26";` in your configuration.nix
        2. Deploy the new configuration

        Then run the following on your nix-bitcoin node:
        1. Move your wallet:
           mv ${dataDir}/wallets/wallet.jmdat ${dataDir}/wallets/old.jmdat
        2. Autogenerate a new p2wpkh wallet:
           systemctl restart joinmarket
        3. Transfer your funds manually by doing sweeps for each mixdepth:
           jm-sendpayment -m <mixdepth> -N 0 old.jmdat 0 <destaddr>

           Run this command for every available mixdepth (`-m 0`, `-m 1`, ...).
           IMPORTANT: Use a different <destaddr> for every run.

           Explanation of the options:
           -m <mixdepth>: spend from given mixdepth.
           -N 0: don't coinjoin on this spend
           old.jmdat: spend from old wallet
           0: set amount to zero to do a sweep, i.e. transfer all funds at given mixdepth
           <destaddr>: destination p2wpkh address from wallet.jmdat with mixdepth 0

        Privacy Notes:
        - This method transfers all funds to the same mixdepth 0.
          Because wallet inputs at the same mixdepth can be considered to be linked, this undoes
          the unlinking effects of previous coinjoins and resets all funds to mixdepth 0.
          This only applies in case that the inputs to the new wallet are used for further coinjoins.
          When inputs are instead kept separate in future transactions, the unlinking effects of
          different mixdepths are preserved.
        - A different <destaddr> should be used for every transaction.
        - You might want to time stagger the transactions.
        - Additionally, you can use coin-freezing to exclude specific inputs from the sweep.

        More information at
        https://github.com/JoinMarket-Org/joinmarket-clientserver/blob/v0.8.0/docs/NATIVE-SEGWIT-UPGRADE.md
      '';
    }
    (mkOnionServiceChange "clightning")
    (mkOnionServiceChange "lnd")
    (mkOnionServiceChange "btcpayserver")
    {
      version = "0.0.41";
      condition = config.services.lnd.enable || config.services.joinmarket.enable;
      message = let
        secretsDir = config.nix-bitcoin.secretsDir;
        lnd = config.services.lnd;
        jm = config.services.joinmarket;
      in ''
        Secret files generated by services at runtime are now stored in the service
        data dirs instead of the global secrets dir.

        To migrate, run the following Bash script as root on your nix-bitcoin node:

          if [[ -e ${secretsDir}/lnd-seed-mnemonic ]]; then
            install -o ${lnd.user} -g ${lnd.group} -m400 "${secretsDir}/lnd-seed-mnemonic" "${lnd.dataDir}"
          fi
          if [[ -e ${secretsDir}/jm-wallet-seed ]]; then
            install -o ${jm.user} -g ${jm.group} -m400 "${secretsDir}/jm-wallet-seed" "${jm.dataDir}"
          fi
          rm -f "${secretsDir}"/{lnd-seed-mnemonic,jm-wallet-seed}
      '';
    }
    {
      version = "0.0.49";
      condition = config.services.joinmarket.enable;
      message = ''
        Starting with 0.21.0, bitcoind no longer automatically creates and loads a
        default wallet named `wallet.dat` [1].
        The joinmarket service now automatically creates a watch-only bitcoind wallet
        (named by option `services.joinmarket.rpcWalletFile`) when creating a joinmarket wallet.

        If you've used JoinMarket before, add the following to your configuration to
        continue using the default `wallet.dat` wallet:
        services.joinmarket.rpcWalletFile = null;

        [1] https://github.com/bitcoin/bitcoin/pull/15454
      '';
    }
    {
      version = "0.0.51";
      condition = config.services.joinmarket.enable;
      message = let
        jmDataDir = config.services.joinmarket.dataDir;
      in ''
        Joinmarket 0.9.1 has added support for Fidelity Bonds [1].

        If you've used joinmarket before, do the following to enable Fidelity Bonds in your existing wallet.
        Enabling Fidelity Bonds has no effect if you don't use them.

        1. Deploy the new system config to your node
        2. Run the following on your node:
           # Ensure that the wallet seed exists and rename the wallet
           ls ${jmDataDir}/jm-wallet-seed && mv ${jmDataDir}/wallets/wallet.jmdat{,.bak}
           # This automatically recreates the wallet with Fidelity Bonds support
           systemctl restart joinmarket
           # Remove wallet backup if update was successful
           rm ${jmDataDir}/wallets/wallet.jmdat.bak

        [1] https://github.com/JoinMarket-Org/joinmarket-clientserver/blob/master/docs/fidelity-bonds.md
      '';
    }
    {
      version = "0.0.53";
      condition = config.services.electrs.enable;
      message = let
        dbPath = "${config.services.electrs.dataDir}/mainnet";
      in ''
        Electrs 0.9.0 has switched to a new, more space efficient database format,
        reducing storage demands by ~60% [1].
        When started, electrs will automatically reindex the bitcoin blockchain.
        This can take a few hours, depending on your hardware. The electrs server is
        inactive during reindexing.

        To upgrade, do the following:

        - If you have less than 40 GB of free space [2] on the electrs data dir volume:
          1. Delete the database:
             systemctl stop electrs
             rm -r '${dbPath}'
          2. Deploy the new system config to your node

        - Otherwise:
          1. Deploy the new system config to your node
          2. Check that electrs works as expected and delete the old database:
             rm -r '${dbPath}'

        [1] https://github.com/romanz/electrs/blob/557911e3baf9a000f883a6f619f0518945a7678d/doc/usage.md#upgrading
        [2] This is based on the bitcoin blockchain size as of 2021-09.
            The general formula is, approximately, size_of(${dbPath}) * 0.6
            This includes the final database size (0.4) plus some extra storage (0.2).
      '';
    }
    {
      version = "0.0.57";
      condition = config.nix-bitcoin ? secure-node-preset-enabled && config.services.liquidd.enable;
      message = ''
        The `secure-node.nix` preset does _not_ set `liquidd.prune = 1000` anymore.

          - If you want to keep the same behavior as before, manually set
            `services.liquidd.prune = 1000;` in your configuration.nix.
          - Otherwise, if you want to turn off pruning, you must instruct liquidd
            to reindex by setting `services.liquidd.extraConfig = "reindex=1";`.
            This can be removed after having started liquidd with that option
            once.
      '';
    }
    {
      version = "0.0.65";
      condition = config.nix-bitcoin ? secure-node-preset-enabled &&
                  config.nix-bitcoin.secretsDir == "/etc/nix-bitcoin-secrets";
      message = ''
        The `secure-node.nix` preset does not set the secrets directory
        to "/secrets" anymore.
        Instead, the default location "/etc/nix-bitcoin-secrets" is used.

        To upgrade, choose one of the following:

        - Continue using "/secrets":
          Add `nix-bitcoin.secretsDir = "/secrets";` to your configuration.nix.

        - Move your secrets to the default location:
          Run the following command as root on your node:
          `rsync -a /secrets/ /etc/nix-bitcoin-secrets`.
          You can delete the old "/secrets" directory after deploying the new system
          config to your node.
      '';
    }
    {
      version = "0.0.70";
      condition = config.services.nbxplorer.enable;
      message = ''
        The nbxplorer database backend has changed from DBTrie to Postgresql.
        The new `services.postgresql` database name is `nbxplorer`.
        The migration happens automatically after deploying.
        Migration time for a large server with a 5GB DBTrie database takes about 40 minutes.
        See also: https://github.com/dgarage/NBXplorer/blob/master/docs/Postgres-Migration.md
      '';
    }
    {
      version = "0.0.70";
      condition = config.services.clightning-rest.enable;
      message = ''
        The `cl-rest` service has been renamed to `clightning-rest`.
        and is now available as a standalone service (`services.clightning-rest`).
        Its data dir has moved to `${config.services.clightning-rest.dataDir}`,
        and the service now runs under the clightning user and group.
        The data dir migration happens automatically after deploying.
      '';
    }
    {
      version = "0.0.70";
      condition = config.services.lnd.lndconnectOnion.enable;
      message = ''
        The `lndconnect-rest-onion` binary has been renamed to `lndconnect`.
      '';
    }
    {
      version = "0.0.85";
      condition = config.services.fulcrum.enable;
      message = ''
        Fulcrum 1.9.0 has changed its database format.
        The database update happens automatically and instantly on deployment,
        but you can't switch back to an older Fulcrum version afterwards.
      '';
    }
  ];

  mkOnionServiceChange = service: {
    version = "0.0.30";
    condition = config.services.${service}.enable;
    message = ''
        The onion service for ${service} has been disabled in the default
        configuration (`secure-node.nix`).

        To enable the onion service, add the following to your configuration:
        nix-bitcon.onionServices.${service}.enable = true;
      '';
  };

  version = config.nix-bitcoin.configVersion;

  incompatibleChanges = optionals
    (version != null && versionOlder lastChange)
    (builtins.filter (change: versionOlder change && (change.condition or true)) changes);

  errorMsg = ''

    This version of nix-bitcoin contains the following changes
    that are incompatible with your config (version ${version}):

    ${concatMapStringsSep "\n" (change: ''
      - ${change.message}(This change was introduced in version ${change.version})
    '') incompatibleChanges}
    After addressing the above changes, set nix-bitcoin.configVersion = "${lastChange.version}";
    in your nix-bitcoin configuration.
  '';

  versionOlder = change: (builtins.compareVersions change.version version) > 0;
  lastChange = builtins.elemAt changes (builtins.length changes - 1);
in
{
  imports = [
    ./obsolete-options.nix
  ];

  inherit options;

  config = {
    # Force evaluation. An actual option value is never assigned
    system = optionalAttrs (builtins.length incompatibleChanges > 0) (builtins.throw errorMsg);
  };
}
