package main

import (
	"bytes"
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"html/template"
	"log"
	"math/big"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/ava-labs/avalanche-cli/pkg/vm"
	"github.com/ava-labs/avalanchego/genesis"
	"github.com/ava-labs/avalanchego/ids"
	"github.com/ava-labs/avalanchego/utils/crypto/secp256k1"
	"github.com/ava-labs/avalanchego/utils/perms"
	"github.com/ava-labs/avalanchego/vms/platformvm/txs"
	"github.com/ava-labs/avalanchego/vms/secp256k1fx"
	"github.com/ava-labs/avalanchego/wallet/chain/c"
	"github.com/ava-labs/avalanchego/wallet/chain/x"
	"github.com/ava-labs/avalanchego/wallet/subnet/primary"
	"github.com/ava-labs/avalanchego/wallet/subnet/primary/common"
	"github.com/ava-labs/coreth/plugin/evm"
	"github.com/ava-labs/subnet-evm/commontype"
	"github.com/ava-labs/subnet-evm/core"
	"github.com/ava-labs/subnet-evm/core/types"
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
	nodeIdPathFormat       = "/tmp/data/node-%d/node_id.txt"

	// TODO: pass this in via a variable
	subnetGenesisPath = "/tmp/subnet-genesis/example-subnet-genesis-with-teleporter.json.tmpl"
	etnaContractsPath = "/tmp/contracts"
	// etnaContractsPath = "/Users/tewodrosmitiku/craft/sandbox/avalabs-package/builder/static-files/contracts"

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
	genesisFileOutput    = "/tmp/subnet/%v/genesis.json"

	// delimiters
	allocationDelimiter = ","
	addrAllocDelimiter  = "="

	ValidatorContractAddress  = "0xC0DEBA5E00000000000000000000000000000000"
	ProxyAdminContractAddress = "0xC0FFEE1234567890aBcDEF1234567890AbCdEf34"
	ProxyContractAddress      = "0xFEEDC0DE0000000000000000000000000000000"
	RewardCalculatorAddress   = "0xDEADC0DE00000000000000000000000000000000"
	ValidatorMessagesAddress  = "0xca11ab1e00000000000000000000000000000000"
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

// func main() {
// 	genesisData, err := getEtnaGenesisBytes(genesis.EWOQKey, 4444, "myblockchain")
// 	if err != nil {
// 		fmt.Print("err")
// 	}

// genesisJson := make(map[string]interface{})
// err = json.Unmarshal(genesisData, &genesisJson)
// if err != nil {
// 	fmt.Print("err")
// }

// prettyJSON, err := json.MarshalIndent(genesisJson, "", "  ")
// if err != nil {
// 	// return fmt.Errorf("failed to marshal genesis: %s\n", err)
// 	fmt.Print("err")
// }
// 	fmt.Println(string(prettyJSON))
// }

// func main() {
// 	// Example private key in hex (do not use this in production!)
// 	privateKeyHex := "56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027"

// 	// Convert hex string to ECDSA private key
// 	privateKey, err := crypto.HexToECDSA(privateKeyHex)
// 	if err != nil {
// 		log.Fatalf("Failed to convert hex to private key: %v", err)
// 	}

// 	// Derive public key from private key
// 	publicKey := privateKey.Public()
// 	publicKeyECDSA, ok := publicKey.(*ecdsa.PublicKey)
// 	if !ok {
// 		log.Fatalf("Failed to cast public key to ECDSA")
// 	}

// 	// Derive Ethereum address from public key
// 	address := crypto.PubkeyToAddress(*publicKeyECDSA)
// 	fmt.Printf("Ethereum address: %s\n", address.Hex())
// }

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
	isEtnaSubnetArg := os.Args[isEtnaSubnetIndex]
	isEtnaSubnet, err := strconv.ParseBool(isEtnaSubnetArg)
	if err != nil {
		fmt.Printf("an error occurred converting is etna subnet '%v' to bool", isEtnaSubnet)
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

		var genesisData []byte
		var genesisJsonFile []byte
		if isEtnaSubnet {
			genesisData, err = getEtnaGenesisBytes(genesis.EWOQKey, chainId, chainName)
			if err != nil {
				fmt.Printf("an error occurred getting etna subnet genesis data with chain id '%v':\n %v\n", chainId, err)
				os.Exit(nonZeroExitCode)
			}
			genesisJson := make(map[string]interface{})
			err = json.Unmarshal(genesisData, &genesisJson)
			if err != nil {
				fmt.Print("err")
				os.Exit(nonZeroExitCode)
			}
			genesisJsonFile, err = json.MarshalIndent(genesisJson, "", "  ")
			if err != nil {
				fmt.Print("err")
				os.Exit(nonZeroExitCode)
			}
		} else {
			genesisData, err = insertChainIdIntoSubnetGenesisTmpl(subnetGenesisPath, chainId)
			if err != nil {
				fmt.Printf("an error occurred converting subnet genesis tmpl into genesis data with chain id '%v':\n %v\n", chainId, err)
				os.Exit(nonZeroExitCode)
			}
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

func createBlockChain(w *wallet, subnetId ids.ID, vmId ids.ID, chainName string, genesisData []byte) (ids.ID, string, map[string]string, string, error) {
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

func printBalances(w *wallet) error {
	cChainAssets, err := w.c.Builder().GetBalance()
	if err != nil {
		return fmt.Errorf("could not get balance of wallet: %v", err)
	}
	fmt.Printf("cChain assets amount: %v\n", cChainAssets)
	pChainAssets, err := w.p.P().Builder().GetBalance()
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

func BytesToAddress(b []byte) [20]byte {
	var a [20]byte
	if len(b) > len(a) {
		b = b[len(b)-20:]
	}
	copy(a[20-len(b):], b)
	return a
}

func getEtnaGenesisBytes(ownerKey *secp256k1.PrivateKey, chainID int, subnetName string) ([]byte, error) {
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

	hexValue := "ffff86ac351052600000"
	bigIntValue := new(big.Int)
	_, success := bigIntValue.SetString(hexValue, 16)
	if !success {
		fmt.Println("Failed to parse the hex value")
	}

	txSpammerAddress, err := evm.ParseEthAddress("8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC")
	if err != nil {
		fmt.Println("Failed to parse the hex value")
	}

	// TODO: what r these two addresses doing?
	otherAddress, err := evm.ParseEthAddress("8943545177806ED17B9F23F0a21ee5948eCaa776")
	if err != nil {
		fmt.Println("Failed to parse the hex value")
	}
	otherAddressTwo, err := evm.ParseEthAddress("78af694930E98D18AB69C04E57071850d8Aa05dC")
	if err != nil {
		fmt.Println("Failed to parse the hex value")
	}
	otherAddressThree, err := evm.ParseEthAddress("8d6699fe55244cb471837f3f80e602d0ccf2665e")
	if err != nil {
		fmt.Println("Failed to parse the hex value")
	}

	allocation := types.GenesisAlloc{
		// FIXME: This looks like a bug in the CLI, CLI allocates funds to a zero address here
		// It is filled in here: https://github.com/ava-labs/avalanche-cli/blob/6debe4169dce2c64352d8c9d0d0acac49e573661/pkg/vm/evm_prompts.go#L178
		ethAddr:           types.Account{Balance: bigIntValue},
		txSpammerAddress:  types.Account{Balance: bigIntValue},
		otherAddress:      types.Account{Balance: bigIntValue},
		otherAddressTwo:   types.Account{Balance: bigIntValue},
		otherAddressThree: types.Account{Balance: bigIntValue},
	}

	// add teleporter contracts
	// teleporter.AddICMMessengerContractToAllocations(allocation)

	// add contracts needed for etna
	proxyAdminBytecode, err := loadHexFile(fmt.Sprintf("%v/proxy_compiled/deployed_proxy_admin_bytecode.txt", etnaContractsPath))
	if err != nil {
		log.Fatalf("❌ Failed to get proxy admin deployed bytecode: %s\n", err)
	}

	transparentProxyBytecode, err := loadHexFile(fmt.Sprintf("%v/proxy_compiled/deployed_transparent_proxy_bytecode.txt", etnaContractsPath))
	if err != nil {
		log.Fatalf("❌ Failed to get transparent proxy deployed bytecode: %s\n", err)
	}

	validatorMessagesBytecode, err := loadDeployedHexFromJSON(fmt.Sprintf("%v/compiled/ValidatorMessages.json", etnaContractsPath), nil)
	if err != nil {
		log.Fatalf("❌ Failed to get validator messages deployed bytecode: %s\n", err)
	}

	poaValidatorManagerLinkRefs := map[string]string{
		"contracts/validator-manager/ValidatorMessages.sol:ValidatorMessages": ValidatorMessagesAddress[2:],
	}
	poaValidatorManagerDeployedBytecode, err := loadDeployedHexFromJSON(fmt.Sprintf("%v/compiled/PoAValidatorManager.json", etnaContractsPath), poaValidatorManagerLinkRefs)
	if err != nil {
		log.Fatalf("❌ Failed to get PoA deployed bytecode: %s\n", err)
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

	// Convert genesis to map to add warpConfig
	genesisMap := make(map[string]interface{})
	genesisBytes, err := json.Marshal(genesis)
	if err != nil {
		log.Fatalf("❌ Failed to marshal genesis to map: %s\n", err)
	}
	if err := json.Unmarshal(genesisBytes, &genesisMap); err != nil {
		log.Fatalf("❌ Failed to unmarshal genesis to map: %s\n", err)
	}

	// Add warpConfig to config
	configMap := genesisMap["config"].(map[string]interface{})
	configMap["warpConfig"] = map[string]interface{}{
		"blockTimestamp":               now,
		"quorumNumerator":              67,
		"requirePrimaryNetworkSigners": true,
	}

	genesisBytesWithWarpConfig, err := json.Marshal(genesis)
	if err != nil {
		log.Fatalf("❌ Failed to marshal genesis to map: %s\n", err)
	}
	if err := json.Unmarshal(genesisBytes, &genesisMap); err != nil {
		log.Fatalf("❌ Failed to unmarshal genesis to map: %s\n", err)
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

type compiledJSON struct {
	DeployedBytecode struct {
		Object string `json:"object"`
	} `json:"deployedBytecode"`
}

func loadDeployedHexFromJSON(path string, linkReferences map[string]string) ([]byte, error) {
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
