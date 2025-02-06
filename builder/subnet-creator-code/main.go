package main

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"html/template"
	"log"
	"math/big"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/ava-labs/avalanche-cli/cmd/blockchaincmd"
	"github.com/ava-labs/avalanche-cli/pkg/constants"
	"github.com/ava-labs/avalanche-cli/pkg/contract"
	"github.com/ava-labs/avalanche-cli/pkg/key"
	"github.com/ava-labs/avalanche-cli/pkg/models"
	"github.com/ava-labs/avalanche-cli/pkg/vm"
	"github.com/ava-labs/avalanche-cli/sdk/interchain"
	"github.com/ava-labs/avalanche-cli/sdk/validatormanager"
	"github.com/ava-labs/avalanchego/genesis"
	"github.com/ava-labs/avalanchego/ids"
	"github.com/ava-labs/avalanchego/staking"
	avagoconstants "github.com/ava-labs/avalanchego/utils/constants"
	"github.com/ava-labs/avalanchego/utils/crypto/bls"
	"github.com/ava-labs/avalanchego/utils/crypto/secp256k1"
	"github.com/ava-labs/avalanchego/utils/formatting/address"
	"github.com/ava-labs/avalanchego/utils/logging"
	"github.com/ava-labs/avalanchego/utils/perms"
	"github.com/ava-labs/avalanchego/utils/set"
	"github.com/ava-labs/avalanchego/vms/platformvm/signer"
	"github.com/ava-labs/avalanchego/vms/platformvm/txs"
	"github.com/ava-labs/avalanchego/vms/platformvm/warp"
	"github.com/ava-labs/avalanchego/vms/platformvm/warp/message"
	"github.com/ava-labs/avalanchego/vms/platformvm/warp/payload"
	"github.com/ava-labs/avalanchego/vms/secp256k1fx"
	"github.com/ava-labs/avalanchego/wallet/chain/c"
	"github.com/ava-labs/avalanchego/wallet/chain/x"
	"github.com/ava-labs/avalanchego/wallet/subnet/primary"
	"github.com/ava-labs/avalanchego/wallet/subnet/primary/common"
	"github.com/ava-labs/coreth/plugin/evm"
	poavalidatormanager "github.com/ava-labs/icm-contracts/abi-bindings/go/validator-manager/PoAValidatorManager"
	"github.com/ava-labs/subnet-evm/accounts/abi/bind"
	"github.com/ava-labs/subnet-evm/commontype"
	"github.com/ava-labs/subnet-evm/core"
	"github.com/ava-labs/subnet-evm/core/types"
	"github.com/ava-labs/subnet-evm/ethclient"
	"github.com/ava-labs/subnet-evm/interfaces"
	"github.com/ava-labs/subnet-evm/params"
	geth_common "github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
)

const (
	uriIndex               = 1
	vmIDArgIndex           = 2
	chainNameIndex         = 3
	numValidatorNodesIndex = 4
	isEtnaSubnetIndex      = 5
	l1CounterIndex         = 6
	chainIdIndex           = 7
	operationIndex         = 8
	minArgs                = 8
	nonZeroExitCode        = 1

	basePath = "/Users/tewodrosmitiku/craft/sandbox/avalabs-package/builder/static-files"
	// basePath = "/tmp/subnet-genesis"
	subnetEvmGenesisPath  = basePath + "/example-subnetevm-genesis-with-teleporter.json.tmpl"
	morpheusVmGenesisPath = basePath + "/example-morpheusvm-genesis.json.tmpl"
	etnaContractsPath     = basePath + "/contracts"

	// validate from a minute after now
	startTimeDelayFromNow = 10 * time.Minute
	// validate for 14 days
	endTimeFromStartTime = 28 * 24 * time.Hour
	// random stake weight of 200
	stakeWeight = uint64(200)

	// outputs
	tmpDir = "/Users/tewodrosmitiku/craft/sandbox/avalabs-package/builder/tmp"
	// tmpDir                    = "/tmp"
	nodeStakingInfoPathFormat = tmpDir + "/data/node-%d/staking"
	nodeIdPathFormat          = tmpDir + "/data/node-%d/node_id.txt"
	parentPath                = tmpDir + "/subnet/%v/node-%d"
	validatorIdsOutput        = tmpDir + "/subnet/%v/node-%d/validator_id.txt"
	subnetIdParentPath        = tmpDir + "/subnet/%v"
	subnetIdOutput            = tmpDir + "/subnet/%v/subnetId.txt"
	blockchainIdOutput        = tmpDir + "/subnet/%v/blockchainId.txt"
	hexChainIdOutput          = tmpDir + "/subnet/%v/hexChainId.txt"
	genesisChainIdOutput      = tmpDir + "/subnet/%v/genesisChainId.txt"
	allocationsOutput         = tmpDir + "/subnet/%v/allocations.txt"
	genesisFileOutput         = tmpDir + "/subnet/%v/genesis.json"

	// delimiters
	allocationDelimiter = ","
	addrAllocDelimiter  = "="

	MorpheusVmId                   = "pkEmJQuTUic3dxzg8EYnktwn4W7uCHofNcwiYo458vodAUbY7"
	HelperAddressesBalanceHexValue = "ffff86ac351052600000"
	TeleporterDeployerAddress      = "0x618FEdD9A45a8C456812ecAAE70C671c6249DfaC"
	TxSpammerAddress               = "0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC"
	ValidatorContractAddress       = "0xC0DEBA5E00000000000000000000000000000000"
	ProxyAdminContractAddress      = "0xC0FFEE1234567890aBcDEF1234567890AbCdEf34"
	ProxyContractAddress           = "0xFEEDC0DE0000000000000000000000000000000"
	RewardCalculatorAddress        = "0xDEADC0DE00000000000000000000000000000000"
	ValidatorMessagesAddress       = "0xca11ab1e00000000000000000000000000000000"

	KurtosisAvalancheLocalNetworkId = 1337
)

type wallet struct {
	p *primary.Wallet
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
	defaultPoll            = common.WithPollFrequency(500 * time.Millisecond)
	defaultPoAOwnerBalance = new(big.Int).Mul(vm.OneAvax, big.NewInt(100))
)

func main() {
	if len(os.Args) < minArgs {
		fmt.Printf("need at least '%v' args got '%v'\n", minArgs, len(os.Args))
		os.Exit(nonZeroExitCode)
	}

	uri := os.Args[uriIndex]
	vmIDStr := os.Args[vmIDArgIndex]
	chainName := os.Args[chainNameIndex]
	numValidatorNodesArg := os.Args[numValidatorNodesIndex]
	numValidatorNodes, err := strconv.Atoi(numValidatorNodesArg)
	if err != nil {
		fmt.Printf("an error occurred while converting numValidatorNodes arg to integer: %v\n", err)
		os.Exit(nonZeroExitCode)
	}
	isEtnaSubnetArg := os.Args[isEtnaSubnetIndex]
	isEtnaSubnet, err := strconv.ParseBool(isEtnaSubnetArg)
	if err != nil {
		fmt.Printf("an error occurred converting is etna subnet '%v' to bool", isEtnaSubnet)
	}
	l1NumArg := os.Args[l1CounterIndex]
	l1Num, err := strconv.Atoi(l1NumArg)
	if err != nil {
		fmt.Printf("an error occurred while converting l1Num arg to integer: %v\n", err)
		os.Exit(nonZeroExitCode)
	}
	chainIdArg := os.Args[chainIdIndex]
	chainId, err := strconv.Atoi(chainIdArg)
	if err != nil {
		fmt.Printf("an error occurred while converting chain id arg to integer: %v\n", err)
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

		var genesisData []byte
		if isEtnaSubnet {
			genesisData, err = getEtnaSubnetEVMGenesisBytes(genesis.EWOQKey, chainId, chainName)
			if err != nil {
				fmt.Printf("an error occurred getting etna subnet evm genesis data with chain id '%v':\n %v\n", chainId, err)
				os.Exit(nonZeroExitCode)
			}
			fmt.Println("created genesis for: etna subnet evm")
		} else if vmID.String() == MorpheusVmId {
			genesisData, err = getMorpheusVMGenesisBytes(chainId, subnetId.String())
			if err != nil {
				fmt.Printf("an error occurred getting morpheusvm genesis data with chain id '%v':\n %v\n", chainId, err)
				os.Exit(nonZeroExitCode)
			}
			fmt.Println("created genesis for: morpheusevm")
		} else {
			genesisData, err = getSubnetEVMGenesisBytes(subnetEvmGenesisPath, chainId)
			if err != nil {
				fmt.Printf("an error occurred converting subnet evm genesis tmpl into genesis data with chain id '%v':\n %v\n", chainId, err)
				os.Exit(nonZeroExitCode)
			}
			fmt.Println("created genesis for: subnetevm")
		}
		var genesisJsonFile []byte
		genesisJson := make(map[string]interface{})
		err = json.Unmarshal(genesisData, &genesisJson)
		if err != nil {
			fmt.Printf("an error occurred unmarshaling genesis data into map:\n%v", genesisData)
			os.Exit(nonZeroExitCode)
		}
		genesisJsonFile, err = json.MarshalIndent(genesisJson, "", "  ")
		if err != nil {
			fmt.Printf("an error occurred marshaling genesis map into formatted json:\n%v", genesisJson)
			os.Exit(nonZeroExitCode)
		}

		blockchainId, hexChainId, allocations, genesisChainId, err := createBlockChain(w, subnetId, vmID, chainName, genesisData)
		if err != nil {
			fmt.Printf("an error occurred while creating chain: %v\n", err)
			os.Exit(nonZeroExitCode)
		}
		fmt.Printf("chain created with id '%v' and vm id '%v'\n", blockchainId, vmID)

		err = writeCreateOutputs(subnetId, vmID, blockchainId, hexChainId, genesisChainId, allocations, l1Num, string(genesisJsonFile))
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

		blockchainIdPath := fmt.Sprintf(subnetIdOutput, l1Num)
		blockchainIdBytes, err := os.ReadFile(blockchainIdPath)
		if err != nil {
			fmt.Printf("an error occurred reading blockchain id '%v' file: %v", blockchainIdPath, err)
			os.Exit(nonZeroExitCode)
		}
		fmt.Printf("retrieved blockchain id '%v'\n", string(subnetIdBytes))
		blockchainId, err := ids.FromString(string(blockchainIdBytes))
		if err != nil {
			fmt.Printf("an error converting blockchain id '%v' to bytes: %v", string(blockchainIdBytes), err)
			os.Exit(nonZeroExitCode)
		}

		w, err := newWalletWithSubnet(uri, subnetId)
		if err != nil {
			fmt.Printf("an error with creating subnet id wallet")
			os.Exit(nonZeroExitCode)
		}

		// var validatorIds []ids.ID
		// validatorIds, err = addSubnetValidators(w, subnetId, numValidatorNodes)
		// if err != nil {
		// 	fmt.Printf("an error occurred while adding validators: %v\n", err)
		// 	os.Exit(nonZeroExitCode)
		// }
		// fmt.Printf("validators added with ids '%v'\n", validatorIds)
		// err = writeAddValidatorsOutput(subnetId, validatorIds)
		// if err != nil {
		// 	fmt.Printf("an error occurred while writing add validators outputs: %v\n", err)
		// 	os.Exit(nonZeroExitCode)
		// }

		converstionTxId, err := convertSubnetToL1(w, subnetId, blockchainId, numValidatorNodes)
		if err != nil {
			fmt.Printf("an error occurred while converting subnet to l1: %v\n", err)
			os.Exit(nonZeroExitCode)
		}
		fmt.Printf("subnet '%v' validating chain '%v' has been converted to l1 with tx '%s'", subnetId.String(), blockchainId.String(), converstionTxId.String())

		err = initializeValidatorManagerContract(subnetId, blockchainId, uri)
		if err != nil {
			fmt.Printf("an error occurred while initializing validator manager contract subnet to l1: %v\n", err)
			os.Exit(nonZeroExitCode)
		}

		err = initializeValidatorSet(subnetId, blockchainId, numValidatorNodes, uri)
		if err != nil {
			fmt.Printf("an error occurred while initializing validator set: %v\n", err)
			os.Exit(nonZeroExitCode)
		}
	default:
		fmt.Println("Operation not supported.")
		os.Exit(nonZeroExitCode)
	}
	os.Exit(0)
}

func writeCreateOutputs(subnetId ids.ID, vmId ids.ID, blockchainId ids.ID, hexChainId string, genesisChainId string, allocations map[string]string, l1Num int, genesisJsonFile string) error {
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
	if err := os.WriteFile(fmt.Sprintf(genesisFileOutput, subnetId.String()), []byte(genesisJsonFile), perms.ReadOnly); err != nil {
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

func newWallet(uri string) (*wallet, error) {
	ctx := context.Background()
	fmt.Println(genesis.EWOQKey)
	fmt.Println(genesis.EWOQKey.Address())
	kc := secp256k1fx.NewKeychain(genesis.EWOQKey)

	// MakeWallet fetches the available UTXOs owned by [kc] on the network that [uri] is hosting.
	walletSyncStartTime := time.Now()
	createdWallet, err := primary.MakeWallet(ctx, uri, kc, kc, primary.WalletConfig{
		SubnetIDs:     []ids.ID{},
		ValidationIDs: []ids.ID{},
	})
	if err != nil {
		log.Fatalf("failed to initialize wallet: %s\n", err)
	}
	log.Printf("synced wallet in %s\n", time.Since(walletSyncStartTime))

	return &wallet{
		p: createdWallet,
		x: createdWallet.X(),
		c: createdWallet.C(),
	}, nil
}

func newWalletWithSubnet(uri string, subnetId ids.ID) (*wallet, error) {
	ctx := context.Background()
	fmt.Println(genesis.EWOQKey)
	fmt.Println(genesis.EWOQKey.Address())
	kc := secp256k1fx.NewKeychain(genesis.EWOQKey)

	// MakeWallet fetches the available UTXOs owned by [kc] on the network that [uri] is hosting.
	walletSyncStartTime := time.Now()
	createdWallet, err := primary.MakeWallet(ctx, uri, kc, kc, primary.WalletConfig{
		SubnetIDs:     []ids.ID{subnetId},
		ValidationIDs: []ids.ID{},
	})
	if err != nil {
		log.Fatalf("failed to initialize wallet: %s\n", err)
	}
	log.Printf("synced wallet in %s\n", time.Since(walletSyncStartTime))

	return &wallet{
		p: createdWallet,
		x: createdWallet.X(),
		c: createdWallet.C(),
	}, nil
}

func createBlockChain(w *wallet, subnetId ids.ID, vmId ids.ID, chainName string, genesisData []byte) (ids.ID, string, map[string]string, string, error) {
	var genesisChainId string
	allocations := map[string]string{}
	if vmId.String() != MorpheusVmId {
		var genesis Genesis
		if err := json.Unmarshal(genesisData, &genesis); err != nil {
			return ids.Empty, "", nil, "", fmt.Errorf("an error occured while unmarshalling genesis json: %v", genesisData)
		}
		for addr, allocation := range genesis.Alloc {
			allocations[addr] = allocation.Balance
		}
		genesisChainId = fmt.Sprintf("%d", genesis.Config.ChainId)
	}
	var nilFxIds []ids.ID
	createChainTx, err := w.p.P().IssueCreateChainTx(
		subnetId,
		genesisData,
		vmId,
		nilFxIds,
		chainName,
	)
	if err != nil {
		return ids.Empty, "", nil, "", fmt.Errorf("an error occured while creating chain for subnet '%v':\n%v", subnetId.String(), err.Error())
	}
	return createChainTx.ID(), createChainTx.TxID.Hex(), allocations, genesisChainId, nil
}

func createSubnet(w *wallet) (ids.ID, error) {
	ctx := context.Background()
	addr := genesis.EWOQKey.PublicKey().Address()
	createSubnetTx, err := w.p.P().IssueCreateSubnetTx(
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

func addSubnetValidators(w *wallet, subnetId ids.ID, numValidators int) ([]ids.ID, error) {
	ctx := context.Background()
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
		addValidatorTx, txErr = w.p.P().IssueAddSubnetValidatorTx(
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
		if txErr != nil {
			return nil, fmt.Errorf("an error occurred while adding node '%v' as validator: %v", index, txErr)
		}
		validatorIDs = append(validatorIDs, addValidatorTx.ID())
	}

	return validatorIDs, nil
}

func getSubnetEVMGenesisBytes(subnetGenesisFilePath string, chainId int) ([]byte, error) {
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

func getEtnaSubnetEVMGenesisBytes(ownerKey *secp256k1.PrivateKey, chainID int, subnetName string) ([]byte, error) {
	ethAddr := evm.PublicKeyToEthAddress(ownerKey.PublicKey())

	now := time.Now().Unix()

	feeConfig := commontype.FeeConfig{
		GasLimit:                 big.NewInt(12000000),
		TargetBlockRate:          2,
		MinBaseFee:               big.NewInt(25000000000),
		TargetGas:                big.NewInt(60000000),
		BaseFeeChangeDenominator: big.NewInt(36),
		MinBlockGasCost:          big.NewInt(0),
		MaxBlockGasCost:          big.NewInt(1000000),
		BlockGasCostStep:         big.NewInt(200000),
	}

	helperAddressesBalanceBigIntValue := new(big.Int)
	_, isSuccess := helperAddressesBalanceBigIntValue.SetString(HelperAddressesBalanceHexValue, 16)
	if !isSuccess {
		return []byte{}, errors.New("failed to parse hex value for funding helper addresses")
	}

	txSpammerAddress, err := evm.ParseEthAddress(TxSpammerAddress)
	if err != nil {
		return []byte{}, fmt.Errorf("failed to parse eth address for tx spammer address: %v\n%v", TxSpammerAddress, err.Error())
	}

	teleporterDeployerAddress, err := evm.ParseEthAddress(TeleporterDeployerAddress)
	if err != nil {
		return []byte{}, fmt.Errorf("failed to parse eth address for teleporter deployer address: %v\n%v", TeleporterDeployerAddress, err.Error())
	}

	otherAddress, err := evm.ParseEthAddress("8943545177806ED17B9F23F0a21ee5948eCaa776")
	if err != nil {
		return []byte{}, fmt.Errorf("failed to parse eth address: %v\n%v", "8943545177806ED17B9F23F0a21ee5948eCaa776", err.Error())
	}
	otherAddressTwo, err := evm.ParseEthAddress("78af694930E98D18AB69C04E57071850d8Aa05dC")
	if err != nil {
		return []byte{}, fmt.Errorf("failed to parse eth address: %v\n%v", "78af694930E98D18AB69C04E57071850d8Aa05dC", err.Error())
	}
	otherAddressThree, err := evm.ParseEthAddress("8d6699fe55244cb471837f3f80e602d0ccf2665e")
	if err != nil {
		return []byte{}, fmt.Errorf("failed to parse eth address: %v\n%v", "8d6699fe55244cb471837f3f80e602d0ccf2665e", err.Error())
	}

	allocation := types.GenesisAlloc{
		// FIXME: This looks like a bug in the CLI, CLI allocates funds to a zero address here
		// It is filled in here: https://github.com/ava-labs/avalanche-cli/blob/6debe4169dce2c64352d8c9d0d0acac49e573661/pkg/vm/evm_prompts.go#L178
		ethAddr:                   types.Account{Balance: helperAddressesBalanceBigIntValue},
		txSpammerAddress:          types.Account{Balance: helperAddressesBalanceBigIntValue},
		teleporterDeployerAddress: types.Account{Balance: helperAddressesBalanceBigIntValue},
		otherAddress:              types.Account{Balance: helperAddressesBalanceBigIntValue},
		otherAddressTwo:           types.Account{Balance: helperAddressesBalanceBigIntValue},
		otherAddressThree:         types.Account{Balance: helperAddressesBalanceBigIntValue},
	}

	// add contracts needed for etna
	proxyAdminBytecode, err := loadHexFile(fmt.Sprintf("%v/proxy_compiled/deployed_proxy_admin_bytecode.txt", etnaContractsPath))
	if err != nil {
		return []byte{}, fmt.Errorf("failed to load hex file for proxy admin bytecode: %s", err.Error())
	}

	transparentProxyBytecode, err := loadHexFile(fmt.Sprintf("%v/proxy_compiled/deployed_transparent_proxy_bytecode.txt", etnaContractsPath))
	if err != nil {
		return []byte{}, fmt.Errorf("failed to load hex file for transparent proxy bytecode: %s", err.Error())
	}

	validatorMessagesBytecode, err := loadDeployedHexFromJSON(fmt.Sprintf("%v/compiled/ValidatorMessages.json", etnaContractsPath), nil)
	if err != nil {
		return []byte{}, fmt.Errorf("failed to load hex file from json for validator messages bytecode: %s", err.Error())
	}

	poaValidatorManagerLinkRefs := map[string]string{
		"contracts/validator-manager/ValidatorMessages.sol:ValidatorMessages": ValidatorMessagesAddress[2:],
	}
	poaValidatorManagerDeployedBytecode, err := loadDeployedHexFromJSON(fmt.Sprintf("%v/compiled/PoAValidatorManager.json", etnaContractsPath), poaValidatorManagerLinkRefs)
	if err != nil {
		return []byte{}, fmt.Errorf("failed to load hex file from json for poa validator manager bytecode: %s", err.Error())
	}

	allocation[geth_common.HexToAddress(ValidatorMessagesAddress)] = types.Account{
		Code:    validatorMessagesBytecode,
		Balance: big.NewInt(0),
		Nonce:   1,
	}

	allocation[geth_common.HexToAddress(ValidatorContractAddress)] = types.Account{
		Code:    poaValidatorManagerDeployedBytecode,
		Balance: big.NewInt(0),
		Nonce:   1,
	}

	allocation[geth_common.HexToAddress(ProxyAdminContractAddress)] = types.Account{
		Balance: big.NewInt(0),
		Code:    proxyAdminBytecode,
		Nonce:   1,
		Storage: map[geth_common.Hash]geth_common.Hash{
			geth_common.HexToHash("0x0"): geth_common.HexToHash(ethAddr.String()),
		},
	}

	allocation[geth_common.HexToAddress(ProxyContractAddress)] = types.Account{
		Balance: big.NewInt(0),
		Code:    transparentProxyBytecode,
		Nonce:   1,
		Storage: map[geth_common.Hash]geth_common.Hash{
			geth_common.HexToHash("0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"): geth_common.HexToHash(ValidatorContractAddress),
			geth_common.HexToHash("0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"): geth_common.HexToHash(ProxyAdminContractAddress),
		},
	}

	genesis := core.Genesis{
		Config: &params.ChainConfig{
			BerlinBlock:         big.NewInt(0),
			ByzantiumBlock:      big.NewInt(0),
			ConstantinopleBlock: big.NewInt(0),
			EIP150Block:         big.NewInt(0),
			EIP155Block:         big.NewInt(0),
			EIP158Block:         big.NewInt(0),
			HomesteadBlock:      big.NewInt(0),
			IstanbulBlock:       big.NewInt(0),
			LondonBlock:         big.NewInt(0),
			MuirGlacierBlock:    big.NewInt(0),
			PetersburgBlock:     big.NewInt(0),
			FeeConfig:           feeConfig,
			ChainID:             big.NewInt(int64(chainID)),
		},
		Alloc:      allocation,
		Difficulty: big.NewInt(0),
		GasLimit:   uint64(12000000),
		Timestamp:  uint64(now),
	}

	genesisBytes, err := json.Marshal(genesis)
	if err != nil {
		return []byte{}, fmt.Errorf("failed to marshal genesis to bytes: %s", err.Error())
	}

	// convert genesis to map to add warpConfig
	genesisMap := make(map[string]interface{})
	if err := json.Unmarshal(genesisBytes, &genesisMap); err != nil {
		return []byte{}, fmt.Errorf("failed to unmarshal genesis bytes to map: %s", err.Error())
	}

	// add warpConfig to config
	configMap := genesisMap["config"].(map[string]interface{})
	configMap["warpConfig"] = map[string]interface{}{
		"blockTimestamp":  now,
		"quorumNumerator": 67,
	}

	genesisBytesWithWarpConfig, err := json.Marshal(genesisMap)
	if err != nil {
		return []byte{}, fmt.Errorf("failed to unmarshal genesis map with warp config: %s", err.Error())
	}

	return genesisBytesWithWarpConfig, nil
}

func loadHexFile(path string) ([]byte, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	// Handle 0x prefix if present
	if len(data) > 1 && data[0] == '0' && data[1] == 'x' {
		data = data[2:]
	}
	// Trim whitespace and newlines
	cleanData := []byte(strings.TrimSpace(string(data)))
	return hex.DecodeString(string(cleanData))
}

func loadDeployedHexFromJSON(path string, linkReferences map[string]string) ([]byte, error) {
	type compiledJSON struct {
		DeployedBytecode struct {
			Object string `json:"object"`
		} `json:"deployedBytecode"`
	}

	compiled := compiledJSON{}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	err = json.Unmarshal(data, &compiled)
	if err != nil {
		return nil, err
	}

	resultHex := compiled.DeployedBytecode.Object

	if linkReferences != nil {
		for refName, address := range linkReferences {
			if len(address) != 40 {
				return nil, fmt.Errorf("invalid placeholder length %d, expected 40: %s", len(address), address)
			}
			if _, err := hex.DecodeString(address); err != nil {
				return nil, fmt.Errorf("invalid hex in placeholder address: %s", address)
			}

			linkRefHash := crypto.Keccak256Hash([]byte(refName))
			linkRefHashStr := linkRefHash.Hex()
			placeholderStr := fmt.Sprintf("__$%s$__", linkRefHashStr[2:36])

			fmt.Printf("Replacing %s with %s\n", placeholderStr, address)

			resultHex = strings.Replace(resultHex, placeholderStr, address, -1)
		}
	}

	if strings.Contains(resultHex, "$__") {
		return nil, fmt.Errorf("unresolved link reference found in bytecode: %s", resultHex)
	}

	// Handle 0x prefix if present
	if len(resultHex) > 1 && resultHex[0] == '0' && resultHex[1] == 'x' {
		resultHex = resultHex[2:]
	}

	return hex.DecodeString(resultHex)
}

func getMorpheusVMGenesisBytes(chainId int, subnetId string) ([]byte, error) {
	tmpl, err := template.ParseFiles(morpheusVmGenesisPath)
	if err != nil {
		return nil, err
	}
	data := struct {
		ChainId   int
		NetworkId string
	}{
		ChainId:   chainId,
		NetworkId: subnetId,
	}
	var buf bytes.Buffer
	err = tmpl.Execute(&buf, data)
	if err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func convertSubnetToL1(w *wallet, subnetId ids.ID, chainId ids.ID, numValidators int) (ids.ID, error) {
	kc := secp256k1fx.NewKeychain(genesis.EWOQKey)
	softKey, err := key.NewSoft(KurtosisAvalancheLocalNetworkId, key.WithPrivateKey(genesis.EWOQKey)) // 1337 is the network id, why thats needed? pass that in via args
	if err != nil {
		return ids.Empty, fmt.Errorf("failed to create change owner address: %w", err)
	}
	changeOwnerAddress := softKey.P()[0] // whats the change owner address?

	fmt.Printf("Using changeOwnerAddress: %s\n", changeOwnerAddress)

	subnetAuthKeys, err := address.ParseToIDs([]string{changeOwnerAddress})
	if err != nil {
		return ids.Empty, fmt.Errorf("failed to parse subnet auth keys: %w", err)
	}

	managerAddress := geth_common.HexToAddress(ProxyContractAddress)
	options := getMultisigTxOptions(subnetAuthKeys, kc)

	var validators []models.SubnetValidator
	for i := 0; i < numValidators; i++ {
		nodeID, proofOfPossession, err := NodeInfoFromCreds(fmt.Sprintf(nodeStakingInfoPathFormat, i))
		if err != nil {
			return ids.Empty, fmt.Errorf("failed to get node info from creds: %w", err)
		}

		publicKey := "0x" + hex.EncodeToString(proofOfPossession.PublicKey[:])
		pop := "0x" + hex.EncodeToString(proofOfPossession.ProofOfPossession[:])

		validator := models.SubnetValidator{
			NodeID:               nodeID.String(),
			Weight:               constants.BootstrapValidatorWeight,
			Balance:              1000000000,
			BLSPublicKey:         publicKey,
			BLSProofOfPossession: pop,
			ChangeOwnerAddr:      changeOwnerAddress,
		}
		validators = append(validators, validator)
	}

	avaGoBootstrapValidators, err := blockchaincmd.ConvertToAvalancheGoSubnetValidator(validators)
	if err != nil {
		return ids.Empty, fmt.Errorf("failed to convert to AvalancheGo subnet validator: %w", err)
	}

	tx, err := w.p.P().IssueConvertSubnetToL1Tx(
		subnetId,
		chainId,
		managerAddress.Bytes(),
		avaGoBootstrapValidators,
		options...,
	)
	if err != nil {
		return ids.Empty, fmt.Errorf("an error occurred issueing convert subnet to l1 tx: %v", err)
	}

	return tx.TxID, nil
}

func NodeInfoFromCreds(folder string) (ids.NodeID, *signer.ProofOfPossession, error) {
	if !strings.HasSuffix(folder, "/") {
		folder += "/"
	}

	blsKey, err := LoadBLSKey(folder + "signer.key")
	if err != nil {
		return ids.NodeID{}, nil, fmt.Errorf("failed to load BLS key: %w", err)
	}

	pop := signer.NewProofOfPossession(blsKey)
	certString, err := LoadText(folder + "staker.crt")
	if err != nil {
		return ids.NodeID{}, nil, fmt.Errorf("failed to load certificate: %w", err)
	}

	block, _ := pem.Decode([]byte(certString))
	if block == nil || block.Type != "CERTIFICATE" {
		panic("failed to decode PEM block containing certificate")
	}

	cert, err := staking.ParseCertificate(block.Bytes)
	if err != nil {
		panic("failed to decode PEM block containing certificate")
	}

	nodeID := ids.NodeIDFromCert(cert)

	return nodeID, pop, nil
}

func LoadBLSKey(path string) (*bls.SecretKey, error) {
	keyBytes, err := LoadBytes(path)
	if err != nil {
		return nil, err
	}
	key, err := bls.SecretKeyFromBytes(keyBytes)
	if err != nil {
		return nil, fmt.Errorf("parsing BLS key from %s: %w", path, err)
	}
	return key, nil
}

func LoadBytes(path string) ([]byte, error) {
	bytes, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("loading bytes from %s: %w", path, err)
	}
	return bytes, nil
}

func LoadText(path string) (string, error) {
	textBytes, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("loading text from %s: %w", path, err)
	}
	return strings.TrimSpace(string(textBytes)), nil
}

func getMultisigTxOptions(subnetAuthKeys []ids.ShortID, kc *secp256k1fx.Keychain) []common.Option {
	options := []common.Option{}
	walletAddrs := kc.Addresses().List()
	changeAddr := walletAddrs[0]
	// addrs to use for signing
	customAddrsSet := set.Set[ids.ShortID]{}
	customAddrsSet.Add(walletAddrs...)
	customAddrsSet.Add(subnetAuthKeys...)
	options = append(options, common.WithCustomAddresses(customAddrsSet))
	// set change to go to wallet addr (instead of any other subnet auth key)
	changeOwner := &secp256k1fx.OutputOwners{
		Threshold: 1,
		Addrs:     []ids.ShortID{changeAddr},
	}
	options = append(options, common.WithChangeOwner(changeOwner))
	return options
}

func initializeValidatorManagerContract(subnetId ids.ID, blockchainId ids.ID, nodeRpcUri string) error {
	ecdsaKey, err := crypto.ToECDSA(genesis.EWOQKey.Bytes())
	if err != nil {
		return fmt.Errorf("failed to load private key: %w", err)
	}

	managerAddress := geth_common.HexToAddress(ProxyContractAddress)

	ethClient, evmChainId, err := GetLocalEthClient(nodeRpcUri, blockchainId.String())
	if err != nil {
		return fmt.Errorf("failed to connect to client: %w", err)
	}

	opts, err := bind.NewKeyedTransactorWithChainID(genesis.EWOQKey.ToECDSA(), evmChainId)
	if err != nil {
		return fmt.Errorf("failed to create transactor: %w", err)
	}
	opts.GasLimit = 8000000
	opts.GasPrice = nil

	_, tx, err := initializeValidatorManagerPoA("poa", managerAddress, ethClient, subnetId, opts, ecdsaKey.PublicKey)
	if err != nil {
		return fmt.Errorf("failed to initialize validator manager: %w", err)
	}

	fmt.Printf("Validator Manager initialized: %v\n", tx.Hash().Hex())
	return nil
}

func initializeValidatorManagerPoA(validatorManagerType string, managerAddress geth_common.Address, ethClient ethclient.Client, subnetID ids.ID, opts *bind.TransactOpts, ecdsaPubKey ecdsa.PublicKey) (*types.Receipt, *types.Transaction, error) {
	logs, err := ethClient.FilterLogs(context.Background(), interfaces.FilterQuery{
		Addresses: []geth_common.Address{managerAddress},
	})
	if err != nil {
		return nil, nil, fmt.Errorf("failed to get contract logs: %w", err)
	}

	// Replace sleep with transaction wait
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	contract, err := poavalidatormanager.NewPoAValidatorManager(managerAddress, ethClient)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create contract instance: %w", err)
	}
	for _, vLog := range logs {
		if _, err := contract.ParseInitialized(vLog); err == nil {
			log.Printf("Validator manager was already initialized")
			return nil, nil, nil
		}
	}

	tx, err := contract.Initialize(opts, poavalidatormanager.ValidatorManagerSettings{
		L1ID:                   subnetID,
		ChurnPeriodSeconds:     0,
		MaximumChurnPercentage: 20,
	}, crypto.PubkeyToAddress(ecdsaPubKey))
	if err != nil {
		return nil, nil, fmt.Errorf("failed to initialize validator manager: %w", err)
	}

	receipt, err := bind.WaitMined(ctx, ethClient, tx)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to wait for transaction confirmation: %w", err)
	}

	return receipt, tx, nil
}

func GetLocalEthClient(nodeRpcUri string, blockchainId string) (ethclient.Client, *big.Int, error) {
	const maxAttempts = 100
	nodeURL := fmt.Sprintf("%s/ext/bc/%s/rpc", nodeRpcUri, blockchainId)

	var err error
	var client ethclient.Client
	var evmChainId *big.Int
	var lastErr error

	sleepSeconds := 5

	for i := 0; i < maxAttempts; i++ {
		if i > 0 {
			log.Printf("Attempt %d/%d to connect to node (will sleep for %d seconds before retry)",
				i+1, maxAttempts, sleepSeconds)
		}

		client, err = ethclient.DialContext(context.Background(), nodeURL)
		if err != nil {
			lastErr = fmt.Errorf("failed to connect to node: %s", err)
			if i > 0 {
				fmt.Printf("Failed to connect: %s\n", err)
			}
			time.Sleep(time.Duration(sleepSeconds) * time.Second)
			continue
		}

		evmChainId, err = client.ChainID(context.Background())
		if err != nil {
			lastErr = fmt.Errorf("failed to get chain ID: %s", err)
			if i > 0 {
				log.Printf("chain is not ready yet: %s (will sleep for %d seconds before retry)\n",
					strings.TrimSpace(string(lastErr.Error())), sleepSeconds)
			}
			time.Sleep(time.Duration(sleepSeconds) * time.Second)
			continue
		}

		return client, evmChainId, nil
	}

	return nil, nil, fmt.Errorf("failed after %d attempts with error: %w", maxAttempts, lastErr)
}

func initializeValidatorSet(subnetId ids.ID, blockchainId ids.ID, numValidators int, nodeRpcUri string) error {
	managerAddress := geth_common.HexToAddress(ProxyContractAddress)

	type InitialValidatorPayload struct {
		NodeID       []byte
		BlsPublicKey []byte
		Weight       uint64
	}
	var validators []message.SubnetToL1ConversionValidatorData
	var validatorPayloads []InitialValidatorPayload
	for i := 0; i < numValidators; i++ {
		nodeID, proofOfPossession, err := NodeInfoFromCreds(fmt.Sprintf(nodeStakingInfoPathFormat, i))
		if err != nil {
			return fmt.Errorf("failed to get node info from creds: %w", err)
		}

		validator := message.SubnetToL1ConversionValidatorData{
			NodeID:       nodeID[:],
			BLSPublicKey: proofOfPossession.PublicKey,
			Weight:       constants.BootstrapValidatorWeight,
		}
		validators = append(validators, validator)
		validatorPayloads = append(validatorPayloads, InitialValidatorPayload{
			NodeID:       validator.NodeID,
			BlsPublicKey: validator.BLSPublicKey[:],
			Weight:       validator.Weight,
		})
	}

	subnetConversionData := message.SubnetToL1ConversionData{
		SubnetID:       subnetId,
		ManagerChainID: blockchainId,
		ManagerAddress: managerAddress.Bytes(),
		Validators:     validators,
	}
	subnetConversionId, err := message.SubnetToL1ConversionID(subnetConversionData)
	if err != nil {
		return fmt.Errorf("failed to create subnet conversion ID: %w", err)
	}

	addressedCallPayload, err := message.NewSubnetToL1Conversion(subnetConversionId)
	if err != nil {
		return fmt.Errorf("failed to create addressed call payload: %w", err)
	}

	subnetConversionAddressedCall, err := payload.NewAddressedCall(
		nil,
		addressedCallPayload.Bytes(),
	)
	if err != nil {
		return fmt.Errorf("failed to create addressed call payload: %w", err)
	}

	network := models.NewLocalNetwork() // careful - under the hood this sets the endpoint as the localhost endpoint which won't connect to the node when this is run inside the enclave

	subnetConversionUnsignedMessage, err := warp.NewUnsignedMessage(
		network.ID,
		avagoconstants.PlatformChainID,
		subnetConversionAddressedCall.Bytes(),
	)
	if err != nil {
		return fmt.Errorf("failed to create unsigned message: %w", err)
	}

	peers, err := blockchaincmd.ConvertURIToPeers([]string{nodeRpcUri}) // do we need to aggregate signatures from all the peers? if so we need to get the node rpc uri's of all the peers
	if err != nil {
		return fmt.Errorf("failed to get extra peers: %w", err)
	}

	signatureAggregator, err := interchain.NewSignatureAggregator(
		network,
		logging.Level(logging.Info),
		subnetId,
		interchain.DefaultQuorumPercentage,
		true,
		peers,
	)
	if err != nil {
		return fmt.Errorf("failed to create signature aggregator: %w", err)
	}

	subnetConversionSignedMessage, err := signatureAggregator.Sign(subnetConversionUnsignedMessage, subnetId[:])
	if err != nil {
		return fmt.Errorf("failed to sign subnet conversion unsigned message: %w", err)
	}

	type SubnetConversionDataPayload struct {
		SubnetID                     [32]byte
		ValidatorManagerBlockchainID [32]byte
		ValidatorManagerAddress      geth_common.Address
		InitialValidators            []InitialValidatorPayload
	}

	subnetConversionDataPayload := SubnetConversionDataPayload{
		SubnetID:                     subnetId,
		ValidatorManagerBlockchainID: blockchainId,
		ValidatorManagerAddress:      managerAddress,
		InitialValidators:            validatorPayloads,
	}

	tx, _, err := contract.TxToMethodWithWarpMessage(
		fmt.Sprintf("%s/ext/bc/%s/rpc", nodeRpcUri, blockchainId),
		strings.TrimSpace(genesis.EWOQKey.String()),
		managerAddress,
		subnetConversionSignedMessage,
		big.NewInt(0),
		"initialize validator set",
		validatormanager.ErrorSignatureToError,
		"initializeValidatorSet((bytes32,bytes32,address,[(bytes,bytes,uint64)]),uint32)",
		subnetConversionDataPayload,
		uint32(0),
	)
	if err != nil {
		return fmt.Errorf("failed to initialize validator set: %w", err)
	}

	fmt.Printf(" Successfully initialized validator set. Transaction hash: %s\n", tx.Hash().String())

	return nil
}
