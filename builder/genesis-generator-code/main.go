package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"sync"
	"time"

	"github.com/ava-labs/avalanche-network-runner/utils"
	"github.com/ava-labs/avalanchego/genesis"
	"github.com/ava-labs/avalanchego/ids"
	"github.com/ava-labs/avalanchego/staking"
	"github.com/ava-labs/avalanchego/utils/crypto/bls"
	"github.com/ava-labs/avalanchego/utils/perms"
	"github.com/ava-labs/avalanchego/vms/platformvm/signer"
)

const (
	signingNodeKeyPath  = "/tmp/data/node-%d/staking/signer.key"
	stakingNodeKeyPath  = "/tmp/data/node-%d/staking/staker.key"
	stakingNodeCertPath = "/tmp/data/node-%d/staking/staker.crt"
	nodeIdPath          = "/tmp/data/node-%d/node_id.txt"
	vmIdPath            = "/tmp/data/vmId.txt"
	genesisFile         = "/tmp/data/genesis.json"
	vmNameArgIndex      = 3
	numNodeArgIndex     = 2
	networkIdIndex      = 1
	minRequiredArgs     = vmNameArgIndex + 1
	nonZeroExitCode     = 1
)

func main() {
	if len(os.Args) < minRequiredArgs {
		fmt.Printf("Need at least %v args got '%v' total\n", minRequiredArgs, len(os.Args))
		os.Exit(nonZeroExitCode)
	}

	numNodesArg := os.Args[numNodeArgIndex]
	numNodes, err := strconv.Atoi(numNodesArg)
	if err != nil {
		fmt.Printf("An error occurred while converting numNodes arg to integer: %v\n", err)
		os.Exit(nonZeroExitCode)
	}

	networkIdArg := os.Args[networkIdIndex]
	var networkId int
	if networkIdArg == "fuji" {
		networkId = 5
	} else {
		networkId, err = strconv.Atoi(networkIdArg)
		if err != nil {
			fmt.Printf("An error occurred while converting networkId arg to integer: %v\n", err)
			os.Exit(nonZeroExitCode)
		}
	}

	vmName := os.Args[vmNameArgIndex]

	fmt.Printf("Have a total of '%v' nodes to generate and network id '%v'\n", numNodes, networkId)

	// Every Node is a validator node for now
	var wg sync.WaitGroup
	genesisValidators := make([]ids.NodeID, numNodes)
	validatorsProofOfPossessions := make([]*signer.ProofOfPossession, numNodes)
	wg.Add(numNodes)
	for index := 0; index < numNodes; index++ {
		go func(index int) {
			defer wg.Done()
			keyPath := fmt.Sprintf(stakingNodeKeyPath, index)
			certPath := fmt.Sprintf(stakingNodeCertPath, index)
			err = staking.InitNodeStakingKeyPair(keyPath, certPath)
			if err != nil {
				fmt.Printf("An error occurred while generating keys for node %v: %v\n", index, err)
				os.Exit(nonZeroExitCode)
			}
			fmt.Printf("Generated key and cert for node '%v' at '%v', '%v\n", index, keyPath, certPath)
			cert, err := staking.LoadTLSCertFromFiles(keyPath, certPath)
			if err != nil {
				fmt.Printf("an error occurred while loading cert pair for node '%v': %v\n", index, err)
				os.Exit(nonZeroExitCode)
			}
			stakingCert := staking.Certificate{
				Raw: cert.Leaf.Raw, PublicKey: cert.Leaf.PublicKey,
			}
			nodeId := ids.NodeIDFromCert(&stakingCert)
			if err = os.WriteFile(fmt.Sprintf(nodeIdPath, index), []byte(nodeId.String()), perms.ReadOnly); err != nil {
				fmt.Printf("an error occurred while writing out node id for node '%v': %v", index, err)
				os.Exit(nonZeroExitCode)
			}

			// need to add signer keys for avalanche warp messaging
			blsSk, err := bls.NewSecretKey()
			if err != nil {
				fmt.Printf("could not create bls secret key for node '%v'\n", nodeId)
				os.Exit(nonZeroExitCode)
			}
			if err = os.WriteFile(fmt.Sprintf(signingNodeKeyPath, index), blsSk.Serialize(), perms.ReadOnly); err != nil {
				fmt.Printf("an error occurred while writing out bls secret key for node '%v': %v", index, err)
				os.Exit(nonZeroExitCode)
			}
			validatorsProofOfPossessions[index] = signer.NewProofOfPossession(blsSk)

			genesisValidators[index] = nodeId
			fmt.Printf("node '%v' has node id '%v'\n", index, nodeId)
		}(index)
	}
	wg.Wait()

	fmt.Printf("generated '%v' nodes\n", len(genesisValidators))

	genesisConfig := genesis.GetConfig(uint32(networkId))
	unparsedConfig, _ := genesisConfig.Unparse()

	var initialStakers []genesis.UnparsedStaker
	basicDelegationFee := 62500
	// give staking reward to random address
	for idx, nodeId := range genesisValidators {
		staker := genesis.UnparsedStaker{
			NodeID:        nodeId,
			RewardAddress: unparsedConfig.Allocations[1].AVAXAddr,
			DelegationFee: uint32(basicDelegationFee),
			Signer:        validatorsProofOfPossessions[idx],
		}
		basicDelegationFee = basicDelegationFee * 2
		initialStakers = append(initialStakers, staker)
	}

	unparsedConfig.StartTime = uint64(time.Now().Unix())

	unparsedConfig.InitialStakers = initialStakers
	genesisJson, err := json.Marshal(unparsedConfig)
	if err != nil {
		fmt.Printf("an error occurred while creating json for genesis: %v\n", err)
		os.Exit(nonZeroExitCode)
	}

	if err = os.WriteFile(genesisFile, genesisJson, perms.ReadOnly); err != nil {
		fmt.Printf("an error occurred while writing out genesis file: %v", err)
		os.Exit(nonZeroExitCode)
	}
	fmt.Printf("generated genesis data at '%v'\n", genesisFile)

	vmID, err := utils.VMID(vmName)
	if err != nil {
		fmt.Printf("an error occurred while creating vmid for vmname '%v'", vmName)
		os.Exit(nonZeroExitCode)
	}

	if err := os.WriteFile(vmIdPath, []byte(vmID.String()), perms.ReadOnly); err != nil {
		fmt.Printf("an error occurred writing vm id '%v' to file '%v': %v", vmID, vmIdPath, err)
	}
}
