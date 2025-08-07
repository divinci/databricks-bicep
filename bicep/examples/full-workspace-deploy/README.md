# Full Workspace Deployment Example

This example demonstrates how to deploy a complete Databricks workspace configuration using the Bicep modules. It creates a comprehensive setup including instance pools, clusters, and jobs that represent a typical production environment.

## Resources Created

### Infrastructure
- **Shared Instance Pool**: A cost-effective pool of compute resources with preloaded Spark versions
- **Production Cluster**: Auto-scaling cluster using the instance pool for production workloads
- **Development Cluster**: Fixed-size cluster for development and testing

### Jobs
- **ETL Job**: Daily scheduled job for data processing using notebook tasks
- **ML Training Job**: On-demand machine learning training job using Python wheel tasks
- **Data Validation Job**: Recurring data validation job using JAR tasks

## Prerequisites

1. **Azure Subscription**: Active Azure subscription with appropriate permissions
2. **Databricks Workspace**: Existing Azure Databricks workspace
3. **Personal Access Token**: Databricks PAT with appropriate permissions
4. **Key Vault**: Azure Key Vault to store the Databricks token securely

## Deployment Steps

### 1. Prepare Parameters

Update the `parameters.json` file with your specific values:

```json
{
  "NamePrefix": {
    "value": "your-company-databricks"
  },
  "WorkspaceUrl": {
    "value": "https://adb-your-workspace-id.azuredatabricks.net"
  },
  "DatabricksToken": {
    "reference": {
      "keyVault": {
        "id": "/subscriptions/your-sub-id/resourceGroups/your-rg/providers/Microsoft.KeyVault/vaults/your-vault"
      },
      "secretName": "databricks-token"
    }
  }
}
```

### 2. Store Databricks Token in Key Vault

```bash
# Create or update the secret in Key Vault
az keyvault secret set \
  --vault-name "your-vault-name" \
  --name "databricks-token" \
  --value "your-databricks-pat-token"
```

### 3. Deploy the Template

```bash
# Create resource group if it doesn't exist
az group create \
  --name "rg-databricks-workspace" \
  --location "East US"

# Deploy the Bicep template
az deployment group create \
  --resource-group "rg-databricks-workspace" \
  --template-file "main.bicep" \
  --parameters "@parameters.json"
```

### 4. Verify Deployment

After successful deployment, you can verify the resources in your Databricks workspace:

1. **Instance Pools**: Check the Compute > Instance Pools section
2. **Clusters**: Verify clusters are created and running in Compute > Clusters
3. **Jobs**: Review scheduled and on-demand jobs in Workflows > Jobs

## Configuration Details

### Instance Pool Configuration
- **Node Type**: Standard_DS3_v2 (can be customized)
- **Capacity**: 1-10 instances with auto-termination after 60 minutes
- **Preloaded Versions**: Spark 13.3.x and 12.2.x
- **Storage**: Premium SSD with 100GB per instance

### Production Cluster
- **Auto-scaling**: 2-8 workers based on workload
- **Runtime**: Photon engine for improved performance
- **Optimizations**: Delta Lake and adaptive query execution enabled
- **Auto-termination**: 120 minutes of inactivity

### Development Cluster
- **Fixed Size**: 2 workers for consistent development environment
- **Auto-termination**: 60 minutes to reduce costs
- **Basic Configuration**: Standard Spark settings

### Job Configurations

#### ETL Job
- **Schedule**: Daily at 2:00 AM UTC
- **Task Type**: Notebook execution
- **Cluster**: Uses production cluster
- **Libraries**: Pandas and NumPy for data processing
- **Notifications**: Email alerts on success/failure

#### ML Training Job
- **Trigger**: On-demand execution
- **Task Type**: Python wheel package
- **Libraries**: Scikit-learn and XGBoost
- **Timeout**: 4 hours for long-running training

#### Data Validation Job
- **Schedule**: Every 4 hours
- **Task Type**: JAR execution
- **Cluster**: Creates new cluster per run
- **Concurrency**: Up to 3 concurrent runs

## Customization

### Adding New Resources

To add additional resources, create new module references in `main.bicep`:

```bicep
module newCluster '../modules/cluster.bicep' = {
  name: 'new-cluster'
  params: {
    ClusterName: '${NamePrefix}-new-cluster'
    // ... other parameters
  }
}
```

### Modifying Configurations

Update the parameters in each module call to customize:
- Cluster sizes and auto-scaling settings
- Job schedules and notification settings
- Library dependencies and Spark configurations
- Tags and naming conventions

### Environment-Specific Deployments

Create separate parameter files for different environments:
- `parameters.dev.json` for development
- `parameters.staging.json` for staging
- `parameters.prod.json` for production

## Monitoring and Maintenance

### Cost Optimization
- Monitor instance pool utilization
- Adjust auto-termination settings based on usage patterns
- Review cluster auto-scaling metrics

### Performance Tuning
- Monitor job execution times and resource usage
- Adjust cluster configurations based on workload requirements
- Update Spark configurations for optimal performance

### Security Best Practices
- Rotate Databricks tokens regularly
- Use managed identities where possible
- Implement proper access controls and workspace permissions

## Troubleshooting

### Common Issues

1. **Token Permissions**: Ensure the Databricks token has sufficient permissions
2. **Resource Limits**: Check Azure subscription limits for compute resources
3. **Network Connectivity**: Verify network access between Azure and Databricks
4. **Library Conflicts**: Review library versions for compatibility

### Debugging Deployment Scripts

Check the deployment script outputs in the Azure portal:
1. Navigate to Resource Groups > Deployments
2. Select the failed deployment
3. Review the deployment script logs for detailed error messages

## Next Steps

After successful deployment:
1. Upload your notebooks and libraries to the workspace
2. Configure data sources and mount points
3. Set up monitoring and alerting
4. Implement CI/CD pipelines for job deployments
5. Configure workspace-level settings and permissions
