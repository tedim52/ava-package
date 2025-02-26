package main

import (
	"encoding/json"
	"os"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestInsertChainIdIntoSubnetGenesisTmpl(t *testing.T) {
	genesisData, err := getMorpheusVMGenesisBytes(55555, "2133143211")
	require.NoError(t, err)

	var genesisJson map[string]interface{}
	err = json.Unmarshal(genesisData, &genesisJson)
	require.NoError(t, err)

	genesisJsonFile, err := json.MarshalIndent(genesisJson, "", "  ")
	require.NoError(t, err)

	genesisJsonPath := "/Users/tewodrosmitiku/craft/sandbox/avalabs-package/builder/static-files/example-morpheusvm-genesis.json"
	err = os.WriteFile(genesisJsonPath, genesisJsonFile, 0777)
	require.NoError(t, err)
}

// func TestGetEtnaGenesisBytes(t *testing.T) {
// 	genesisData, err := getEtnaGenesisBytes(genesis.EWOQKey, 55555, "myblockchain")
// 	require.NoError(t, err)

// 	var prettyJSON bytes.Buffer
// 	err = json.Indent(&prettyJSON, genesisData, "", "    ")
// 	require.NoError(t, err)

// 	err = os.WriteFile("L1-gensesis.json", prettyJSON.Bytes(), 0644)
// 	require.NoError(t, err)
// }

func bytesToJSON(data []byte) (map[string]interface{}, error) {
	var result map[string]interface{}
	err := json.Unmarshal(data, &result)
	if err != nil {
		return nil, err
	}
	return result, nil
}
