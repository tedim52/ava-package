package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"html/template"
	"log"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/ava-labs/avalanchego/wallet/chain/c"

	"github.com/ava-labs/avalanchego/genesis"
	"github.com/ava-labs/avalanchego/ids"
	"github.com/ava-labs/avalanchego/utils/perms"
	"github.com/ava-labs/avalanchego/vms/components/avax"
	"github.com/ava-labs/avalanchego/vms/components/verify"
	"github.com/ava-labs/avalanchego/vms/platformvm/reward"
	"github.com/ava-labs/avalanchego/vms/platformvm/signer"
	"github.com/ava-labs/avalanchego/vms/platformvm/txs"
	"github.com/ava-labs/avalanchego/vms/secp256k1fx"
	pchainwallet "github.com/ava-labs/avalanchego/wallet/chain/p/wallet"
	"github.com/ava-labs/avalanchego/wallet/chain/x"
	"github.com/ava-labs/avalanchego/wallet/subnet/primary"
	"github.com/ava-labs/avalanchego/wallet/subnet/primary/common"
)

const (
	uriIndex               = 1
	vmIDArgIndex           = 2
	chainNameIndex         = 3
	numValidatorNodesIndex = 4
	isElasticIndex         = 5
	l1CounterIndex         = 6
	chainIdIndex           = 7
	operationIndex         = 8
	minArgs                = 8
	nonZeroExitCode        = 1
	nodeIdPathFormat       = "/tmp/data/node-%d/node_id.txt"

	// TODO: pass this in via a variable
	subnetGenesisPath = "/tmp/subnet-genesis/example-subnet-genesis-with-teleporter.json.tmpl"

	// validate from a minute after now
	startTimeDelayFromNow = 10 * time.Minute
	// validate for 14 days
	endTimeFromStartTime = 28 * 24 * time.Hour
	// random stake weight of 200
	stakeWeight = uint64(200)

	// outputs
	// TODO: update these to store based on subnet id
	parentPath           = "/tmp/subnet/%v/node-%d"
	validatorIdsOutput   = "/tmp/subnet/%v/node-%d/validator_id.txt"
	subnetIdParentPath   = "/tmp/subnet/%v"
	subnetIdOutput       = "/tmp/subnet/%v/subnetId.txt"
	blockchainIdOutput   = "/tmp/subnet/%v/blockchainId.txt"
	hexChainIdOutput     = "/tmp/subnet/%v/hexChainId.txt"
	genesisChainIdOutput = "/tmp/subnet/%v/genesisChainId.txt"
	allocationsOutput    = "/tmp/subnet/%v/allocations.txt"

	// permissionless
	assetIdOutput          = "/tmp/subnet/%v/assetId.txt"
	exportIdOutput         = "/tmp/subnet/%v/exportId.txt"
	importIdOutput         = "/tmp/subnet/%v/importId.txt"
	transformationIdOutput = "/tmp/subnet/%v/transformationId.txt"

	// delimiters
	allocationDelimiter = ","
	addrAllocDelimiter  = "="
)

// https://github.com/ava-labs/avalanche-cli/blob/917ef2e440880d68452080b4051c3031be76b8af/pkg/elasticsubnet/config_prompt.go#L18-L38
const (
	defaultInitialSupply            = 240_000_000
	defaultMaximumSupply            = 720_000_000
	defaultMinConsumptionRate       = 0.1 * reward.PercentDenominator
	defaultMaxConsumptionRate       = 0.12 * reward.PercentDenominator
	defaultMinValidatorStake        = 2_000
	defaultMaxValidatorStake        = 3_000_000
	defaultMinStakeDurationHours    = 14 * 24
	defaultMinStakeDuration         = defaultMinStakeDurationHours * time.Hour
	defaultMaxStakeDurationHours    = 365 * 24
	defaultMaxStakeDuration         = defaultMaxStakeDurationHours * time.Hour
	defaultMinDelegationFee         = 20_000
	defaultMinDelegatorStake        = 25
	defaultMaxValidatorWeightFactor = 5
	defaultUptimeRequirement        = 0.8 * reward.PercentDenominator
)

type wallet struct {
	p pchainwallet.Wallet
	x x.Wallet
	c c.Wallet
}

type Genesis struct {
	Alloc  map[string]Balance `json:alloc`
	Config Config             `json:config`
}

type Config struct {
	ChainId int `json:chainId`
}

type Balance struct {
	Balance string `json:balance`
}

var (
	defaultPoll = common.WithPollFrequency(500 * time.Millisecond)
)

// It's usage from builder.star is like this
// subnetId, chainId, validatorIds, allocations, genesisChainId, assetId, transformationId, exportId, importId =
// builder_service.create_subnet(plan, first_private_rpc_url, num_validators, is_elastic, vmId, chainName)
func main() {
	if len(os.Args) < minArgs {
		fmt.Printf("Need at least '%v' args got '%v'\n", minArgs, len(os.Args))
		os.Exit(nonZeroExitCode)
	}

	uri := os.Args[uriIndex]
	vmIDStr := os.Args[vmIDArgIndex]
	chainName := os.Args[chainNameIndex]
	numValidatorNodesArg := os.Args[numValidatorNodesIndex]
	numValidatorNodes, err := strconv.Atoi(numValidatorNodesArg)
	if err != nil {
		fmt.Printf("An error occurred while converting numValidatorNodes arg to integer: %v\n", err)
		os.Exit(nonZeroExitCode)
	}
	isElasticArg := os.Args[isElasticIndex]
	isElastic, err := strconv.ParseBool(isElasticArg)
	if err != nil {
		fmt.Printf("an error occurred converting is elastic '%v' to bool", isElastic)
	}
	l1NumArg := os.Args[l1CounterIndex]
	l1Num, err := strconv.Atoi(l1NumArg)
	if err != nil {
		fmt.Printf("An error occurred while converting l1Num arg to integer: %v\n", err)
		os.Exit(nonZeroExitCode)
	}
	chainIdArg := os.Args[chainIdIndex]
	chainId, err := strconv.Atoi(chainIdArg)
	if err != nil {
		fmt.Printf("An error occurred while converting chain id arg to integer: %v\n", err)
		os.Exit(nonZeroExitCode)
	}

	operation := os.Args[operationIndex]

	fmt.Printf("trying uri '%v' vmID '%v' chainName '%v' and numValidatorNodes '%v'", uri, vmIDStr, chainName, numValidatorNodes)
	switch operation {
	case "create":
		w, err := newWallet(uri)
		if err != nil {
			fmt.Printf("Couldn't create wallet \n")
			os.Exit(nonZeroExitCode)
		}

		subnetId, err := createSubnet(w)
		if err != nil {
			fmt.Printf("an error occurred while creating subnet: %v\n", err)
			os.Exit(nonZeroExitCode)
		}
		fmt.Printf("subnet created created with id '%v'\n", subnetId)
		subnetId.String()

		vmID, err := ids.FromString(vmIDStr)
		if err != nil {
			fmt.Printf("an error occurred converting '%v' vm id string to ids.ID: %v", vmIDStr, err)
			os.Exit(nonZeroExitCode)
		}

		genesisData, err := insertChainIdIntoSubnetGenesisTmpl(subnetGenesisPath, chainId)
		if err != nil {
			fmt.Printf("an error occurred converting subnet genesis tmpl into genesis data with chain id '%v':\n %v\n", chainId, err)
			os.Exit(nonZeroExitCode)
		}

		blockchainId, hexChainId, allocations, genesisChainId, err := createBlockChain(w, subnetId, vmID, chainName, genesisData)
		if err != nil {
			fmt.Printf("an error occurred while creating chain: %v\n", err)
			os.Exit(nonZeroExitCode)
		}
		fmt.Printf("chain created with id '%v' and vm id '%v'\n", blockchainId, vmID)

		err = writeCreateOutputs(subnetId, vmID, blockchainId, hexChainId, genesisChainId, allocations, l1Num)
		if err != nil {
			fmt.Printf("an error occurred while writing create outputs: %v\n", err)
			os.Exit(nonZeroExitCode)
		}
	case "addvalidators":
		subnetIdPath := fmt.Sprintf(subnetIdOutput, l1Num)
		subnetIdBytes, err := os.ReadFile(subnetIdPath)
		if err != nil {
			fmt.Printf("an error occurred reading subnet id '%v' file: %v", subnetIdPath, err)
			os.Exit(nonZeroExitCode)
		}
		fmt.Printf("retrieved subnet id '%v'\n", string(subnetIdBytes))
		subnetId, err := ids.FromString(string(subnetIdBytes))
		if err != nil {
			fmt.Printf("an error converting subnet id '%v' to bytes: %v", string(subnetIdBytes), err)
			os.Exit(nonZeroExitCode)
		}

		w, err := newWalletWithSubnet(uri, subnetId)
		if err != nil {
			fmt.Printf("an error with creating subnet id wallet")
			os.Exit(nonZeroExitCode)
		}

		var validatorIds []ids.ID
		validatorIds, err = addSubnetValidators(w, subnetId, numValidatorNodes)
		if err != nil {
			fmt.Printf("an error occurred while adding validators: %v\n", err)
			os.Exit(nonZeroExitCode)
		}
		fmt.Printf("validators added with ids '%v'\n", validatorIds)
		err = writeAddValidatorsOutput(subnetId, validatorIds)
		if err != nil {
			fmt.Printf("an error occurred while writing add validators outputs: %v\n", err)
			os.Exit(nonZeroExitCode)
		}
	default:
		fmt.Println("Operation not supported.")
	}

	// var assetId, exportId, importId, transformationId ids.ID
	// if isElastic {
	// 	assetId, exportId, importId, err = createAssetOnXChainImportToPChain(w, "foo token", "FOO", 9, 100000000000)
	// 	if err != nil {
	// 		fmt.Printf("an error occurred while creating asset: %v\n", err)
	// 		os.Exit(nonZeroExitCode)
	// 	}
	// 	fmt.Printf("created asset '%v' exported with id '%v' and imported with id '%v'\n", assetId, exportId, importId)
	// 	transformationId, err = transformSubnet(w, subnetId, assetId)
	// 	if err != nil {
	// 		fmt.Printf("an error occurred while transforming subnet: %v\n", err)
	// 		os.Exit(nonZeroExitCode)
	// 	}
	// 	fmt.Printf("transformed subnet and got transformation id '%v'\n", transformationId)
	// 	validatorIds, err = addPermissionlessValidator(w, assetId, subnetId, numValidatorNodes)
	// 	if err != nil {
	// 		fmt.Printf("an error occurred while creating permissionless validators: %v\n", err)
	// 		os.Exit(nonZeroExitCode)
	// 	}
	// 	fmt.Printf("added permissionless validators with ids '%v'\n", validatorIds)
	// }

	// err = writeOutputs(subnetId, chainId, validatorIds, allocations, genesisChainId, assetId, exportId, importId, transformationId, isElastic, l1NumArg)
	// if err != nil {
	// 	fmt.Printf("an error occurred while writing outputs: %v\n", err)
	// 	os.Exit(nonZeroExitCode)
	// }
}

func writeCreateOutputs(subnetId ids.ID, vmId ids.ID, blockchainId ids.ID, hexChainId string, genesisChainId string, allocations map[string]string, l1Num int) error {
	if err := os.MkdirAll(fmt.Sprintf(subnetIdParentPath, l1Num), 0700); err != nil {
		return err
	}
	if err := os.MkdirAll(fmt.Sprintf(subnetIdParentPath, l1Num), 0700); err != nil {
		return err
	}
	if err := os.WriteFile(fmt.Sprintf(subnetIdOutput, l1Num), []byte(subnetId.String()), perms.ReadOnly); err != nil {
		return err
	}
	if err := os.MkdirAll(fmt.Sprintf(subnetIdParentPath, subnetId.String()), 0700); err != nil {
		return err
	}
	if err := os.WriteFile(fmt.Sprintf(blockchainIdOutput, subnetId.String()), []byte(blockchainId.String()), perms.ReadOnly); err != nil {
		return err
	}
	if err := os.WriteFile(fmt.Sprintf(hexChainIdOutput, subnetId.String()), []byte(hexChainId), perms.ReadOnly); err != nil {
		return err
	}
	if err := os.WriteFile(fmt.Sprintf(genesisChainIdOutput, subnetId.String()), []byte(genesisChainId), perms.ReadOnly); err != nil {
		return err
	}
	var allocationList []string
	for addr, balance := range allocations {
		allocationList = append(allocationList, addr+addrAllocDelimiter+balance)
	}
	if err := os.WriteFile(fmt.Sprintf(allocationsOutput, subnetId.String()), []byte(strings.Join(allocationList, allocationDelimiter)), perms.ReadOnly); err != nil {
		return err
	}
	return nil
}

func writeAddValidatorsOutput(subnetId ids.ID, validatorIds []ids.ID) error {
	for index, validatorId := range validatorIds {
		if err := os.MkdirAll(fmt.Sprintf(parentPath, subnetId.String(), index), 0700); err != nil {
			return err
		}
		err := os.WriteFile(fmt.Sprintf(validatorIdsOutput, subnetId.String(), index), []byte(validatorId.String()), perms.ReadOnly)
		if err != nil {
			return err
		}
	}
	return nil
}

func writeOutputs(subnetId ids.ID, chainId ids.ID, validatorIds []ids.ID, allocations map[string]string, genesisChainId string, assetId, exportId, importId, transformationId ids.ID, isElastic bool, l1Num string) error {
	if err := os.MkdirAll(fmt.Sprintf(subnetIdParentPath, l1Num), 0700); err != nil {
		return err
	}
	for index, validatorId := range validatorIds {
		if err := os.MkdirAll(fmt.Sprintf(parentPath, subnetId.String(), index), 0700); err != nil {
			return err
		}
		err := os.WriteFile(fmt.Sprintf(validatorIdsOutput, subnetId.String(), index), []byte(validatorId.String()), perms.ReadOnly)
		if err != nil {
			return err
		}
	}
	if err := os.MkdirAll(fmt.Sprintf(subnetIdParentPath, l1Num), 0700); err != nil {
		return err
	}
	if err := os.WriteFile(fmt.Sprintf(subnetIdOutput, l1Num), []byte(subnetId.String()), perms.ReadOnly); err != nil {
		return err
	}
	if err := os.MkdirAll(fmt.Sprintf(subnetIdParentPath, subnetId.String()), 0700); err != nil {
		return err
	}
	// if err := os.WriteFile(fmt.Sprintf(chainIdOutput, subnetId.String()), []byte(chainId.String()), perms.ReadOnly); err != nil {
	// 	return err
	// }
	if err := os.WriteFile(fmt.Sprintf(genesisChainIdOutput, subnetId.String()), []byte(genesisChainId), perms.ReadOnly); err != nil {
		return err
	}
	var allocationList []string
	for addr, balance := range allocations {
		allocationList = append(allocationList, addr+addrAllocDelimiter+balance)
	}
	if err := os.WriteFile(fmt.Sprintf(allocationsOutput, subnetId.String()), []byte(strings.Join(allocationList, allocationDelimiter)), perms.ReadOnly); err != nil {
		return err
	}
	if isElastic {
		if err := os.WriteFile(fmt.Sprintf(assetIdOutput, subnetId.String()), []byte(assetId.String()), perms.ReadOnly); err != nil {
			return err
		}
		if err := os.WriteFile(fmt.Sprintf(exportIdOutput, subnetId.String()), []byte(exportId.String()), perms.ReadOnly); err != nil {
			return err
		}
		if err := os.WriteFile(fmt.Sprintf(importIdOutput, subnetId.String()), []byte(importId.String()), perms.ReadOnly); err != nil {
			return err
		}
		if err := os.WriteFile(fmt.Sprintf(transformationIdOutput, subnetId.String()), []byte(transformationId.String()), perms.ReadOnly); err != nil {
			return err
		}
	}
	return nil
}

func addPermissionlessValidator(w *wallet, assetId ids.ID, subnetId ids.ID, numValidators int) ([]ids.ID, error) {
	ctx := context.Background()
	var validatorIDs []ids.ID
	owner := &secp256k1fx.OutputOwners{
		Threshold: 1,
		Addrs: []ids.ShortID{
			genesis.EWOQKey.PublicKey().Address(),
		},
	}
	for index := 0; index < numValidators; index++ {
		nodeIdPath := fmt.Sprintf(nodeIdPathFormat, index)
		nodeIdBytes, err := os.ReadFile(nodeIdPath)
		if err != nil {
			return nil, fmt.Errorf("an error occurred while reading node id '%v': %v", nodeIdPath, err)
		}
		nodeId, err := ids.NodeIDFromString(string(nodeIdBytes))
		if err != nil {
			return nil, fmt.Errorf("couldn't convert '%v' to node id", string(nodeIdBytes))
		}
		startTime := time.Now().Add(startTimeDelayFromNow)
		endTime := startTime.Add(endTimeFromStartTime)
		validatorTx, err := w.p.IssueAddPermissionlessValidatorTx(
			&txs.SubnetValidator{
				Validator: txs.Validator{
					NodeID: nodeId,
					Start:  uint64(startTime.Unix()),
					End:    uint64(endTime.Unix()),
					Wght:   6000,
				},
				Subnet: subnetId,
			},
			&signer.Empty{},
			assetId,
			owner,
			&secp256k1fx.OutputOwners{},
			reward.PercentDenominator,
			common.WithContext(ctx),
			defaultPoll,
		)
		if err != nil {
			return nil, fmt.Errorf("an error occurred while adding validator '%v': %v", index, err)
		}
		validatorIDs = append(validatorIDs, validatorTx.ID())
	}
	return validatorIDs, nil
}

func transformSubnet(w *wallet, subnetId ids.ID, assetId ids.ID) (ids.ID, error) {
	ctx := context.Background()
	transformSubnetTx, err := w.p.IssueTransformSubnetTx(
		subnetId,
		assetId,
		uint64(defaultInitialSupply),
		uint64(defaultMaximumSupply),
		uint64(defaultMinConsumptionRate),
		uint64(defaultMaxConsumptionRate),
		uint64(defaultMinValidatorStake),
		uint64(defaultMaxValidatorStake),
		defaultMinStakeDuration,
		defaultMaxStakeDuration,
		uint32(defaultMinDelegationFee),
		uint64(defaultMinDelegatorStake),
		byte(defaultMaxValidatorWeightFactor),
		uint32(defaultUptimeRequirement),
		common.WithContext(ctx),
	)
	if err != nil {
		return ids.Empty, err
	}
	return transformSubnetTx.ID(), err
}

func createAssetOnXChainImportToPChain(w *wallet, name string, symbol string, denomination byte, maxSupply uint64) (ids.ID, ids.ID, ids.ID, error) {
	ctx := context.Background()
	owner := &secp256k1fx.OutputOwners{
		Threshold: 1,
		Addrs: []ids.ShortID{
			genesis.EWOQKey.PublicKey().Address(),
		},
	}
	assetTx, err := w.x.IssueCreateAssetTx(
		name,
		symbol,
		denomination,
		// borrowed from https://github.com/ava-labs/avalanche-cli/blob/917ef2e440880d68452080b4051c3031be76b8af/pkg/subnet/local.go#L101C32-L111
		map[uint32][]verify.State{
			0: {
				&secp256k1fx.TransferOutput{
					Amt:          maxSupply,
					OutputOwners: *owner,
				},
			},
		},
		common.WithContext(ctx),
	)
	if err != nil {
		return ids.Empty, ids.Empty, ids.Empty, fmt.Errorf("an error occurred while creating asset: %v", err)
	}
	exportTx, err := w.x.IssueExportTx(
		ids.Empty,
		[]*avax.TransferableOutput{
			{
				Asset: avax.Asset{
					ID: assetTx.ID(),
				},
				Out: &secp256k1fx.TransferOutput{
					Amt:          maxSupply,
					OutputOwners: *owner,
				},
			},
		},
		common.WithContext(ctx),
	)
	if err != nil {
		return ids.Empty, ids.Empty, ids.Empty, fmt.Errorf("an error occurred while issuing asset export: %v", err)
	}
	importTx, err := w.p.IssueImportTx(
		w.x.Builder().Context().BlockchainID,
		owner,
		common.WithContext(ctx),
	)
	if err != nil {
		return ids.Empty, ids.Empty, ids.Empty, fmt.Errorf("an error occurred while issuing asset import: %v", err)
	}
	return assetTx.ID(), exportTx.ID(), importTx.ID(), nil
}

func addSubnetValidators(w *wallet, subnetId ids.ID, numValidators int) ([]ids.ID, error) {
	ctx := context.Background()
	// w, err := newWallet(uri)
	// if err != nil {
	// 	return nil, fmt.Errorf("could not create new wallet for adding subnet validators: %v", err)
	// }
	var validatorIDs []ids.ID
	for index := 0; index < numValidators; index++ {
		nodeIdPath := fmt.Sprintf(nodeIdPathFormat, index)
		nodeIdBytes, err := os.ReadFile(nodeIdPath)
		if err != nil {
			return nil, fmt.Errorf("an error occurred while reading node id '%v': %v", nodeIdPath, err)
		}
		nodeId, err := ids.NodeIDFromString(string(nodeIdBytes))
		if err != nil {
			return nil, fmt.Errorf("couldn't convert '%v' to node id", string(nodeIdBytes))
		}
		startTime := time.Now().Add(startTimeDelayFromNow)
		endTime := startTime.Add(endTimeFromStartTime)
		var addValidatorTx *txs.Tx
		var txErr error
		// retryCount := 30
		// for retryCount > 0 {
		addValidatorTx, txErr = w.p.IssueAddSubnetValidatorTx(
			&txs.SubnetValidator{
				Validator: txs.Validator{
					NodeID: nodeId,
					Start:  uint64(startTime.Unix()),
					End:    uint64(endTime.Unix()),
					Wght:   stakeWeight,
				},
				Subnet: subnetId,
			},
			common.WithContext(ctx),
			defaultPoll,
		)
		// if txErr != nil {
		// 	retryCount -= 1
		// 	fmt.Printf("an error occurred issuing an add subnet validator tx, trying '%v' more times:\n %v\n", retryCount, txErr.Error())
		// 	time.Sleep(30 * time.Second)
		// } else {
		// 	retryCount = 0
		// }
		// }
		if txErr != nil {
			return nil, fmt.Errorf("an error occurred while adding node '%v' as validator: %v", index, txErr)
		}
		validatorIDs = append(validatorIDs, addValidatorTx.ID())
	}

	return validatorIDs, nil
}

func createBlockChain(w *wallet, subnetId ids.ID, vmId ids.ID, chainName string, genesisData []byte) (ids.ID, string, map[string]string, string, error) {
	ctx := context.Background()
	var genesis Genesis
	if err := json.Unmarshal(genesisData, &genesis); err != nil {
		return ids.Empty, "", nil, "", fmt.Errorf("an error occured while unmarshalling genesis json: %v", genesisData)
	}
	allocations := map[string]string{}
	for addr, allocation := range genesis.Alloc {
		allocations[addr] = allocation.Balance
	}
	genesisChainId := fmt.Sprintf("%d", genesis.Config.ChainId)
	var nilFxIds []ids.ID
	createChainTx, err := w.p.IssueCreateChainTx(
		subnetId,
		genesisData,
		vmId,
		nilFxIds,
		chainName,
		common.WithContext(ctx),
		defaultPoll,
	)
	if err != nil {
		return ids.Empty, "", nil, "", nil
	}
	return createChainTx.ID(), createChainTx.TxID.Hex(), allocations, genesisChainId, nil
}

func createSubnet(w *wallet) (ids.ID, error) {
	ctx := context.Background()
	addr := genesis.EWOQKey.PublicKey().Address()
	createSubnetTx, err := w.p.IssueCreateSubnetTx(
		&secp256k1fx.OutputOwners{
			Threshold: 1,
			Addrs:     []ids.ShortID{addr},
		},
		common.WithContext(ctx),
		defaultPoll,
	)
	if err != nil {
		return ids.Empty, err
	}

	return createSubnetTx.ID(), nil
}

func newWalletWithSubnet(uri string, subnetId ids.ID) (*wallet, error) {
	ctx := context.Background()
	fmt.Println(genesis.EWOQKey)
	fmt.Println(genesis.EWOQKey.Address())
	kc := secp256k1fx.NewKeychain(genesis.EWOQKey)

	// MakeWallet fetches the available UTXOs owned by [kc] on the network that [uri] is hosting.
	walletSyncStartTime := time.Now()
	createdWallet, err := primary.MakeWallet(ctx, &primary.WalletConfig{
		URI:          uri,
		AVAXKeychain: kc,
		EthKeychain:  kc,
		SubnetIDs:    []ids.ID{subnetId},
	})
	if err != nil {
		log.Fatalf("failed to initialize wallet: %s\n", err)
	}
	log.Printf("synced wallet in %s\n", time.Since(walletSyncStartTime))

	return &wallet{
		p: createdWallet.P(),
		x: createdWallet.X(),
		c: createdWallet.C(),
	}, nil
}

func newWallet(uri string) (*wallet, error) {
	ctx := context.Background()
	fmt.Println(genesis.EWOQKey)
	fmt.Println(genesis.EWOQKey.Address())
	kc := secp256k1fx.NewKeychain(genesis.EWOQKey)

	// MakeWallet fetches the available UTXOs owned by [kc] on the network that [uri] is hosting.
	walletSyncStartTime := time.Now()
	createdWallet, err := primary.MakeWallet(ctx, &primary.WalletConfig{
		URI:          uri,
		AVAXKeychain: kc,
		EthKeychain:  kc,
	})
	if err != nil {
		log.Fatalf("failed to initialize wallet: %s\n", err)
	}
	log.Printf("synced wallet in %s\n", time.Since(walletSyncStartTime))

	return &wallet{
		p: createdWallet.P(),
		x: createdWallet.X(),
		c: createdWallet.C(),
	}, nil
}

func printBalances(w *wallet) error {
	cChainAssets, err := w.c.Builder().GetBalance()
	if err != nil {
		return fmt.Errorf("could not get balance of wallet: %v", err)
	}
	fmt.Printf("cChain assets amount: %v\n", cChainAssets)
	pChainAssets, err := w.p.Builder().GetBalance()
	if err != nil {
		return fmt.Errorf("could not get balance of wallet: %v", err)
	}
	for id, numAssets := range pChainAssets {
		fmt.Printf("wallet has %v of asset with id %v\n", numAssets, id)
	}
	return nil
}

func insertChainIdIntoSubnetGenesisTmpl(subnetGenesisFilePath string, chainId int) ([]byte, error) {

	tmpl, err := template.ParseFiles(subnetGenesisFilePath)
	if err != nil {
		return nil, err
	}
	data := struct {
		ChainId int
	}{
		ChainId: chainId,
	}
	var buf bytes.Buffer
	err = tmpl.Execute(&buf, data)
	if err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}
