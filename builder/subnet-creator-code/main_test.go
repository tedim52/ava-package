package main

import (
	"bytes"
	"os"
	"testing"

	"encoding/json"

	"github.com/ava-labs/avalanchego/genesis"
	"github.com/stretchr/testify/require"
)

func TestInsertChainIdIntoSubnetGenesisTmpl(t *testing.T) {
	subnetGenesisPath := "/Users/tewodrosmitiku/craft/sandbox/avalabs-package/static-files/example-subnet-genesis-with-teleporter.json.tmpl"
	networkId := 561234
	genesisData, err := insertChainIdIntoSubnetGenesisTmpl(subnetGenesisPath, networkId)
	require.NoError(t, err)

	genesisJson, err := bytesToJSON(genesisData)
	require.NoError(t, err)

	require.Equal(t, networkId, genesisJson["config"])
}

func TestGetEtnaGenesisBytes(t *testing.T) {
	genesisData, err := getEtnaGenesisBytes(genesis.EWOQKey, 55555, "myblockchain")
	require.NoError(t, err)

	var prettyJSON bytes.Buffer
	err = json.Indent(&prettyJSON, genesisData, "", "    ")
	require.NoError(t, err)

	err = os.WriteFile("L1-gensesis.json", prettyJSON.Bytes(), 0644)
	require.NoError(t, err)
}

func bytesToJSON(data []byte) (map[string]interface{}, error) {
	var result map[string]interface{}
	err := json.Unmarshal(data, &result)
	if err != nil {
		return nil, err
	}
	return result, nil
}
