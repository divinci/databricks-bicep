@description('Databricks Operations using Deployment Scripts')
param databricksProviderName string
param databricksProviderResourceGroup string = resourceGroup().name
param clusterId string
param jobId string
param operationType string = 'start'

// Reference existing Databricks custom provider
resource databricksProvider 'Microsoft.CustomProviders/resourceProviders@2018-09-01-preview' existing = {
  name: databricksProviderName
  scope: resourceGroup(databricksProviderResourceGroup)
}

// Start cluster operation
resource startClusterOperation 'Microsoft.Resources/deploymentScripts@2020-10-01' = if (operationType == 'start') {
  name: 'start-databricks-cluster'
  location: 'East US'
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.40.0'
    scriptContent: '''
      echo "Starting Databricks cluster..."
      
      # Call custom provider action to start cluster
      RESPONSE=$(az rest --method POST \
        --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.CustomProviders/resourceProviders/${PROVIDER_NAME}/startCluster?api-version=2018-09-01-preview" \
        --body "{\"clusterId\": \"${CLUSTER_ID}\"}" \
        --headers "Content-Type=application/json")
      
      echo "Start cluster response: $RESPONSE"
      
      # Wait for cluster to be running
      for i in {1..30}; do
        STATUS_RESPONSE=$(az rest --method POST \
          --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.CustomProviders/resourceProviders/${PROVIDER_NAME}/getClusterStatus?api-version=2018-09-01-preview" \
          --body "{\"clusterId\": \"${CLUSTER_ID}\"}" \
          --headers "Content-Type=application/json")
        
        STATE=$(echo $STATUS_RESPONSE | jq -r '.state')
        echo "Cluster state: $STATE"
        
        if [ "$STATE" = "RUNNING" ]; then
          echo "Cluster is now running!"
          break
        elif [ "$STATE" = "ERROR" ] || [ "$STATE" = "TERMINATED" ]; then
          echo "Cluster failed to start. State: $STATE"
          exit 1
        fi
        
        echo "Waiting for cluster to start... (attempt $i/30)"
        sleep 30
      done
    '''
    environmentVariables: [
      {
        name: 'PROVIDER_NAME'
        value: databricksProviderName
      }
      {
        name: 'CLUSTER_ID'
        value: clusterId
      }
      {
        name: 'RESOURCE_GROUP'
        value: resourceGroup().name
      }
      {
        name: 'AZURE_SUBSCRIPTION_ID'
        value: subscription().subscriptionId
      }
    ]
    timeout: 'PT30M'
    retentionInterval: 'P1D'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Stop cluster operation
resource stopClusterOperation 'Microsoft.Resources/deploymentScripts@2020-10-01' = if (operationType == 'stop') {
  name: 'stop-databricks-cluster'
  location: 'East US'
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.40.0'
    scriptContent: '''
      echo "Stopping Databricks cluster..."
      
      RESPONSE=$(az rest --method POST \
        --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.CustomProviders/resourceProviders/${PROVIDER_NAME}/stopCluster?api-version=2018-09-01-preview" \
        --body "{\"clusterId\": \"${CLUSTER_ID}\"}" \
        --headers "Content-Type=application/json")
      
      echo "Stop cluster response: $RESPONSE"
      echo "Cluster stop initiated successfully"
    '''
    environmentVariables: [
      {
        name: 'PROVIDER_NAME'
        value: databricksProviderName
      }
      {
        name: 'CLUSTER_ID'
        value: clusterId
      }
      {
        name: 'RESOURCE_GROUP'
        value: resourceGroup().name
      }
      {
        name: 'AZURE_SUBSCRIPTION_ID'
        value: subscription().subscriptionId
      }
    ]
    timeout: 'PT10M'
    retentionInterval: 'P1D'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Run job operation
resource runJobOperation 'Microsoft.Resources/deploymentScripts@2020-10-01' = if (operationType == 'run-job') {
  name: 'run-databricks-job'
  location: 'East US'
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.40.0'
    scriptContent: '''
      echo "Running Databricks job..."
      
      # Trigger job run
      RUN_RESPONSE=$(az rest --method POST \
        --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.CustomProviders/resourceProviders/${PROVIDER_NAME}/runJob?api-version=2018-09-01-preview" \
        --body "{\"jobId\": \"${JOB_ID}\", \"notebookParams\": {\"environment\": \"production\", \"date\": \"$(date +%Y-%m-%d)\"}}" \
        --headers "Content-Type=application/json")
      
      RUN_ID=$(echo $RUN_RESPONSE | jq -r '.runId')
      echo "Job run started with ID: $RUN_ID"
      
      # Monitor job run status
      for i in {1..60}; do
        STATUS_RESPONSE=$(az rest --method GET \
          --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.CustomProviders/resourceProviders/${PROVIDER_NAME}/jobs/${JOB_ID}/runs/${RUN_ID}?api-version=2018-09-01-preview")
        
        STATE=$(echo $STATUS_RESPONSE | jq -r '.state.lifeState')
        echo "Job run state: $STATE"
        
        if [ "$STATE" = "TERMINATED" ]; then
          RESULT=$(echo $STATUS_RESPONSE | jq -r '.state.resultState')
          echo "Job completed with result: $RESULT"
          
          if [ "$RESULT" = "SUCCESS" ]; then
            echo "Job run completed successfully!"
            break
          else
            echo "Job run failed with result: $RESULT"
            exit 1
          fi
        elif [ "$STATE" = "SKIPPED" ] || [ "$STATE" = "INTERNAL_ERROR" ]; then
          echo "Job run failed with state: $STATE"
          exit 1
        fi
        
        echo "Job still running... (check $i/60)"
        sleep 60
      done
    '''
    environmentVariables: [
      {
        name: 'PROVIDER_NAME'
        value: databricksProviderName
      }
      {
        name: 'JOB_ID'
        value: jobId
      }
      {
        name: 'RESOURCE_GROUP'
        value: resourceGroup().name
      }
      {
        name: 'AZURE_SUBSCRIPTION_ID'
        value: subscription().subscriptionId
      }
    ]
    timeout: 'PT2H'
    retentionInterval: 'P1D'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

output operationResult string = operationType == 'start' ? startClusterOperation.properties.outputs.result : operationType == 'stop' ? stopClusterOperation.properties.outputs.result : runJobOperation.properties.outputs.result
