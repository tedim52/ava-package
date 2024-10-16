package main

import (
	"context"
	"fmt"

	"github.com/ava-labs/avalanchego/ids"
	"github.com/ava-labs/avalanchego/snow/validators"
	"github.com/ava-labs/avalanchego/vms/platformvm"
	"github.com/ava-labs/awm-relayer/utils"
	"github.com/ava-labs/subnet-evm/ethclient"
	"github.com/ava-labs/subnet-evm/precompile/contracts/warp"
	_ "github.com/ava-labs/subnet-evm/precompile/registry"
	"github.com/sirupsen/logrus"
	"go.uber.org/zap"
)

func main() {
	err := compute()
	if err != nil {
		fmt.Printf("%v", err)
	}
}

type WarpQuorum struct {
	QuorumNumerator   uint64
	QuorumDenominator uint64
}

func compute() error {
	blockchainID, err := ids.FromString("PStQWfS8i3TXfmVaefqMgT4NQV5H6FUbCAvEr7tDWQEMCTb8p")
	if err != nil {
		return fmt.Errorf("invalid blockchainID in configuration. error: %w", err)
	}
	subnetId, err := ids.FromString("s5gML9jhJH8qFqAKtg8pPEcsHaomv3SBA7xJzsa7bJEqVHRnW")
	if err != nil {
		return fmt.Errorf("invalid subnetID in configuration. error: %w", err)
	}

	client, err := utils.NewEthClientWithConfig(
		context.Background(),
		"http://localhost:9650/ext/bc/PStQWfS8i3TXfmVaefqMgT4NQV5H6FUbCAvEr7tDWQEMCTb8p/rpc",
		map[string]string{},
		map[string]string{},
	)
	if err != nil {
		return fmt.Errorf("failed to dial destination blockchain %s: %w", blockchainID, err)
	}
	defer client.Close()
	quorum, err := getWarpQuorum(subnetId, blockchainID, client)
	if err != nil {
		return fmt.Errorf("failed to fetch warp quorum for subnet %s: %w", subnetId, err)
	}
	fmt.Println(quorum.QuorumNumerator)
	fmt.Println(quorum.QuorumDenominator)

	validatorOutput, err := getCurrentValidatorSet(context.Background(), subnetId)
	if err != nil {
		fmt.Println(err)
	}
	for _, o := range validatorOutput {
		fmt.Printf("node id: %v\n", o.NodeID)
		fmt.Printf("node public key: %v\n", o.PublicKey)
	}
	return nil
}

func getWarpQuorum(
	subnetID ids.ID,
	blockchainID ids.ID,
	client ethclient.Client,
) (WarpQuorum, error) {
	// Fetch the subnet's chain config
	chainConfig, err := client.ChainConfig(context.Background())
	if err != nil {
		return WarpQuorum{}, fmt.Errorf("failed to fetch chain config for blockchain %s: %w", blockchainID, err)
	}

	// First, check the list of precompile upgrades to get the most up to date Warp config
	// We only need to consider the most recent Warp config, since the QuorumNumerator is used
	// at signature verification time on the receiving chain, regardless of the Warp config at the
	// time of the message's creation
	var warpConfig *warp.Config
	for _, precompile := range chainConfig.UpgradeConfig.PrecompileUpgrades {
		cfg, ok := precompile.Config.(*warp.Config)
		if !ok {
			continue
		}
		if warpConfig == nil {
			warpConfig = cfg
			continue
		}
		if *cfg.Timestamp() > *warpConfig.Timestamp() {
			warpConfig = cfg
		}
	}
	if warpConfig != nil {
		return WarpQuorum{
			QuorumNumerator:   calculateQuorumNumerator(warpConfig.QuorumNumerator),
			QuorumDenominator: warp.WarpQuorumDenominator,
		}, nil
	}

	// If we didn't find the Warp config in the upgrade precompile list, check the genesis config
	warpConfig, ok := chainConfig.GenesisPrecompiles["warpConfig"].(*warp.Config)
	if ok {
		return WarpQuorum{
			QuorumNumerator:   calculateQuorumNumerator(warpConfig.QuorumNumerator),
			QuorumDenominator: warp.WarpQuorumDenominator,
		}, nil
	}
	return WarpQuorum{}, fmt.Errorf("failed to find warp config for blockchain %s", blockchainID)
}

func calculateQuorumNumerator(cfgNumerator uint64) uint64 {
	if cfgNumerator == 0 {
		return warp.WarpDefaultQuorumNumerator
	}
	return cfgNumerator
}

// Gets the current validator set of the given subnet ID, including the validators' BLS public
// keys. The implementation currently makes two RPC requests, one to get the subnet validators,
// and another to get their BLS public keys. This is necessary in order to enable the use of
// the public APIs (which don't support "GetValidatorsAt") because BLS keys are currently only
// associated with primary network validation periods. If ACP-13 is implemented in the future
// (https://github.com/avalanche-foundation/ACPs/blob/main/ACPs/13-subnet-only-validators.md), it
// may become possible to reduce this to a single RPC request that returns both the subnet validators
// as well as their BLS public keys.
func getCurrentValidatorSet(ctx context.Context, subnetID ids.ID) (map[ids.NodeID]*validators.GetValidatorOutput, error) {
	// Get the current subnet validators. These validators are not expected to include
	// BLS signing information given that addPermissionlessValidatorTx is only used to
	client := platformvm.NewClient("http://127.0.0.1:9650")

	subnetVdrs, err := client.GetCurrentValidators(ctx, subnetID, nil)
	if err != nil {
		return nil, err
	}

	// Look up the primary network validators of the NodeIDs validating the subnet
	// in order to get their BLS keys.
	res := make(map[ids.NodeID]*validators.GetValidatorOutput, len(subnetVdrs))
	subnetNodeIDs := make([]ids.NodeID, 0, len(subnetVdrs))
	for _, subnetVdr := range subnetVdrs {
		subnetNodeIDs = append(subnetNodeIDs, subnetVdr.NodeID)
		res[subnetVdr.NodeID] = &validators.GetValidatorOutput{
			NodeID: subnetVdr.NodeID,
			Weight: subnetVdr.Weight,
		}
	}
	primaryVdrs, err := client.GetCurrentValidators(ctx, ids.Empty, subnetNodeIDs)
	if err != nil {
		return nil, err
	}

	// Set the BLS keys of the result.
	for _, primaryVdr := range primaryVdrs {
		// We expect all of the primary network validators to already be in `res` because
		// we filtered the request to node IDs that were identified as validators of the
		// specific subnet ID.
		vdr, ok := res[primaryVdr.NodeID]
		if !ok {
			logrus.Warn(
				"Unexpected primary network validator returned by getCurrentValidators request",
				zap.String("subnetID", subnetID.String()),
				zap.String("nodeID", primaryVdr.NodeID.String()))
			continue
		}

		// Validators that do not have a BLS public key registered on the P-chain are still
		// included in the result because they affect the stake weight of the subnet validators.
		// Such validators will not be queried for BLS signatures of warp messages. As long as
		// sufficient stake percentage of subnet validators have registered BLS public keys,
		// messages can still be successfully relayed.
		if primaryVdr.Signer != nil {
			fmt.Printf("this primary validator does a signer %v: %v\n", primaryVdr.NodeID, primaryVdr.Signer.Key())
			vdr.PublicKey = primaryVdr.Signer.Key()
		} else {
			fmt.Printf("this primary validator does not have a signer %v\n", primaryVdr.NodeID)
		}
	}

	return res, nil
}
