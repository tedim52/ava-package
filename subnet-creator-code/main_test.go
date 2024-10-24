package main

import (
	"testing"

	"encoding/json"

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

func bytesToJSON(data []byte) (map[string]interface{}, error) {
	var result map[string]interface{}
	err := json.Unmarshal(data, &result)
	if err != nil {
		return nil, err
	}
	return result, nil
}
