# Databricks Bicep Provider

This directory contains a comprehensive collection of 94 production-ready Bicep modules for deploying and managing Azure Databricks resources using direct REST API calls through a centralized helper.

## Overview

The Databricks Bicep Provider provides complete Infrastructure as Code (IaC) capabilities for Databricks resources through:
- 94 individual Bicep modules covering all major Databricks resource types
- Centralized `Invoke-DatabricksApi` helper for consistent API interactions
- Comprehensive test coverage using Pester framework with 94 test files
- Complete workspace deployment examples and CI/CD pipeline integration

## Architecture

The provider uses Azure Deployment Scripts to execute PowerShell commands that interact directly with the Databricks REST API:

1. **Centralized Helper**: `helpers/Invoke-DatabricksApi.ps1` handles all API calls with consistent authentication and error handling
2. **Bicep Modules**: Individual modules under `modules/` for each Databricks resource type
3. **Deployment Scripts**: Azure Deployment Scripts execute PowerShell to create/manage resources
4. **Testing Framework**: Pester tests in `tests/` directory for validation

## Available Modules (94 Implemented)

### Core Infrastructure
- `cluster.bicep` - Databricks clusters with auto-scaling and custom configurations
- `instance-pool.bicep` - Instance pools for cost-effective compute resource management
- `job.bicep` - Databricks jobs with scheduling and notification support

### Workspace Management
- `workspace.bicep` - Workspace configuration and settings
- `workspace-conf.bicep` - Workspace configuration parameters
- `workspace-file.bicep` - Workspace file management
- `workspace-binding.bicep` - Workspace binding configurations
- `workspace-asset.bicep` - Workspace asset management
- `workspace-info.bicep` - Workspace information retrieval
- `workspace-status.bicep` - Workspace status monitoring
- `workspace-url.bicep` - Workspace URL management

### Security and Access Control
- `secret-scope.bicep` - Secret management and Key Vault integration
- `secret.bicep` - Individual secret management
- `permissions.bicep` - General access control and permissions
- `cluster-permissions.bicep` - Cluster-specific permissions
- `job-permissions.bicep` - Job-specific permissions
- `sql-permissions.bicep` - SQL warehouse permissions
- `workspace-object-permissions.bicep` - Workspace object permissions
- `permission-assignment.bicep` - Permission assignment management
- `access-control-rule-set.bicep` - Access control rule sets
- `ip-access-list.bicep` - IP access list management

### Data and Storage
- `notebook.bicep` - Notebook deployment and management
- `file.bicep` - File management
- `dbfs-file.bicep` - DBFS file operations
- `directory.bicep` - Directory management
- `mount.bicep` - Storage mount point management
- `library.bicep` - Library installation and management
- `volume.bicep` - Volume management

### Unity Catalog
- `catalog.bicep` - Unity Catalog management
- `schema.bicep` - Schema management
- `table.bicep` - Table management
- `function.bicep` - Function management
- `metastore.bicep` - Metastore configuration
- `external-location.bicep` - External location management
- `storage-credential.bicep` - Storage credential management
- `grant.bicep` - Grant management
- `system-schema.bicep` - System schema management

### Machine Learning
- `mlflow-experiment.bicep` - MLflow experiment management
- `model.bicep` - Model management
- `model-version.bicep` - Model version management
- `model-serving.bicep` - Model serving endpoints
- `registered-model.bicep` - Registered model management
- `external-model.bicep` - External model integration

### SQL and Analytics
- `sql-endpoint.bicep` - SQL endpoint management
- `sql-query.bicep` - SQL query management
- `sql-dashboard.bicep` - SQL dashboard management
- `sql-visualization.bicep` - SQL visualization management
- `warehouse.bicep` - SQL warehouse management

### Governance and Compliance
- `policy.bicep` - Cluster policies and governance
- `cluster-policy.bicep` - Cluster policy management
- `compliance-security-profile.bicep` - Compliance security profiles
- `cluster-compliance-security-profile.bicep` - Cluster compliance profiles
- `enhanced-security-monitoring.bicep` - Enhanced security monitoring

### Multi-Workspace Service (MWS)
- `mws-workspaces.bicep` - Multi-workspace service workspaces
- `mws-credentials.bicep` - MWS credentials management
- `mws-storage-configurations.bicep` - MWS storage configurations
- `mws-networks.bicep` - MWS network configurations
- `mws-customer-managed-keys.bicep` - Customer managed keys
- `mws-log-delivery.bicep` - Log delivery configuration
- `mws-private-access-settings.bicep` - Private access settings
- `mws-vpc-endpoint.bicep` - VPC endpoint management
- `mws-permission-assignment.bicep` - MWS permission assignments

### User and Group Management
- `user.bicep` - User management
- `group.bicep` - Group management
- `service-principal.bicep` - Service principal management
- `entitlements.bicep` - User and group entitlements
- `current-user.bicep` - Current user information

### Monitoring and Operations
- `alert.bicep` - Alert configuration
- `notification-destination.bicep` - Notification destinations
- `budget.bicep` - Budget management
- `quality-monitor.bicep` - Data quality monitoring
- `lakehouse-monitor.bicep` - Lakehouse monitoring

### Advanced Features
- `pipeline.bicep` - Delta Live Tables pipelines
- `vector-search-endpoint.bicep` - Vector search endpoints
- `vector-search-index.bicep` - Vector search indexes
- `online-table.bicep` - Online table management
- `connection.bicep` - Connection management
- `share.bicep` - Delta sharing
- `recipient.bicep` - Delta sharing recipients

### Configuration and Utilities
- `token.bicep` - Token management
- `obo-token.bicep` - On-behalf-of token management
- `git-credential.bicep` - Git credential management
- `global-init-script.bicep` - Global initialization scripts
- `artifact-allowlist.bicep` - Artifact allowlist management
- `custom-app-integration.bicep` - Custom app integration
- `automatic-cluster-update.bicep` - Automatic cluster updates
- `dashboard.bicep` - Dashboard management
- `repo.bicep` - Repository management
- `provider.bicep` - Provider configuration
- `instance-profile.bicep` - Instance profile management
- `cluster-node-type.bicep` - Cluster node type information
- `spark-version.bicep` - Spark version information
- `cluster-library.bicep` - Cluster library management
- `workspace-configuration.bicep` - Workspace configuration management

## Usage

### 1. Basic Cluster Deployment

```bicep
module cluster 'modules/cluster.bicep' = {
  name: 'my-databricks-cluster'
  params: {
    ClusterName: 'production-cluster'
    SparkVersion: '13.3.x-scala2.12'
    NodeTypeId: 'Standard_DS3_v2'
    NumWorkers: 4
    DatabricksToken: databricksToken
    WorkspaceUrl: 'https://adb-123456789.azuredatabricks.net'
    CustomTags: {
      Environment: 'Production'
      Project: 'DataPlatform'
    }
  }
}
```

### 2. Auto-scaling Cluster with Instance Pool

```bicep
module instancePool 'modules/instance-pool.bicep' = {
  name: 'shared-instance-pool'
  params: {
    InstancePoolName: 'shared-compute-pool'
    NodeTypeId: 'Standard_DS3_v2'
    MinIdleInstances: 2
    MaxCapacity: 20
    DatabricksToken: databricksToken
    WorkspaceUrl: workspaceUrl
  }
}

module cluster 'modules/cluster.bicep' = {
  name: 'autoscaling-cluster'
  dependsOn: [instancePool]
  params: {
    ClusterName: 'auto-scaling-cluster'
    AutoScale: true
    MinWorkers: 2
    MaxWorkers: 10
    InstancePoolId: instancePool.outputs.InstancePoolId
    DatabricksToken: databricksToken
    WorkspaceUrl: workspaceUrl
  }
}
```

### 3. Scheduled ETL Job

```bicep
module etlJob 'modules/job.bicep' = {
  name: 'daily-etl-job'
  params: {
    JobName: 'daily-data-processing'
    DatabricksToken: databricksToken
    WorkspaceUrl: workspaceUrl
    JobSettings: {
      notebook_task: {
        notebook_path: '/Shared/ETL/daily-processing'
        base_parameters: {
          environment: 'production'
          date: '{{ds}}'
        }
      }
      existing_cluster_id: cluster.outputs.ClusterId
    }
    Schedule: {
      quartz_cron_expression: '0 0 2 * * ?'
      timezone_id: 'UTC'
    }
    EmailNotifications: {
      on_success: ['data-team@company.com']
      on_failure: ['ops-team@company.com']
    }
  }
}
```

### 4. Complete Workspace Deployment

See the comprehensive working example in `examples/full-workspace-deploy/` which demonstrates:
- Shared instance pool for cost optimization with premium SSD storage
- Production cluster with auto-scaling (2-8 workers) using Photon runtime
- Development cluster with fixed size for consistent testing
- Multiple job types (ETL, ML training, data validation) with different task types
- Proper dependency management and comprehensive resource tagging
- Email notifications and scheduling configurations

## Authentication

### Databricks Personal Access Token

Store your Databricks PAT securely in Azure Key Vault:

```bash
az keyvault secret set \
  --vault-name "your-keyvault" \
  --name "databricks-token" \
  --value "your-databricks-pat"
```

Reference it in your Bicep templates:

```bicep
param databricksToken string = keyVault.getSecret('databricks-token')
```

### Required Permissions

Your Databricks token needs the following permissions:
- Cluster management (create, read, update, delete)
- Job management (create, read, update, delete, run)
- Instance pool management
- Workspace object access (notebooks, libraries)

## Testing

### Running Tests

The comprehensive Pester testing framework includes 94 test files covering all modules. Tests require environment variables:

```powershell
# Set required environment variables
$env:DATABRICKS_WORKSPACE_URL = "https://adb-123456789.azuredatabricks.net"
$env:DATABRICKS_TOKEN = "your-databricks-pat"

# Run all tests (94 test files)
Invoke-Pester -Path "tests/" -Recurse

# Run specific module tests
Invoke-Pester -Path "tests/cluster.Tests.ps1"
Invoke-Pester -Path "tests/job.Tests.ps1"
Invoke-Pester -Path "tests/instance-pool.Tests.ps1"
```

### Test Structure

Each of the 94 modules has corresponding comprehensive tests that cover:
- **Positive Path**: Successful resource creation with various configurations (minimum required, autoscaling, custom configurations)
- **Negative Path**: Validation of error handling and parameter constraints (invalid versions, node types, configurations)
- **Cleanup**: Automatic resource cleanup after test completion using the Invoke-DatabricksApi helper
- **Integration Testing**: Real Databricks API calls to validate functionality

## Development Guidelines

### Adding New Modules

The current implementation includes 94 modules covering all major Databricks resources. When extending with additional modules:

1. **Research the Terraform Resource**: Examine the corresponding Terraform resource in `/internal/.../*.go`
2. **Map Parameters**: Convert Terraform schema to Bicep parameters with proper types and validation
3. **Identify REST API**: Determine the Databricks REST API endpoints and methods
4. **Create Module**: Implement the Bicep module using the established patterns
5. **Add Tests**: Create comprehensive Pester tests following the existing 94-test framework
6. **Update Documentation**: Add usage examples and parameter descriptions

### Coding Standards

- **Parameter Naming**: Use PascalCase for all parameters and outputs
- **Descriptions**: Every parameter and output must have an `@description` annotation
- **Security**: Use `@secure()` for sensitive parameters like tokens and passwords
- **Validation**: Add `@allowed()` constraints where appropriate
- **Dependencies**: Use `dependsOn` for proper resource ordering
- **Error Handling**: Include comprehensive error handling in deployment scripts

### Module Structure Template

```bicep
@description('Description of the main resource identifier')
param ResourceName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

// Additional parameters with proper types and validation

var resourceConfig = {
  // Map parameters to API payload structure
}

resource resourceCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-resource-${uniqueString(ResourceName)}'
  location: resourceGroup().location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '9.0'
    timeout: 'PT30M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'DATABRICKS_TOKEN'
        secureValue: DatabricksToken
      }
      {
        name: 'WORKSPACE_URL'
        value: WorkspaceUrl
      }
      {
        name: 'RESOURCE_CONFIG'
        value: string(resourceConfig)
      }
    ]
    scriptContent: '''
      # PowerShell script using Invoke-DatabricksApi helper
    '''
  }
}

@description('Output description')
output ResourceId string = resourceCreation.properties.outputs.resourceId
```

## CI/CD Pipeline Integration

The bicep provider includes a complete Azure DevOps pipeline (`azure-pipelines.yml`) with:

### Pipeline Stages
1. **Validation Stage**: Bicep template validation using Azure CLI
2. **Staging Deployment**: Automated deployment to staging environment with ETL job testing
3. **Production Deployment**: Conditional deployment to production on main branch

### Pipeline Features
- Automatic template validation on every commit
- Environment-specific deployments with proper approvals
- Integration testing with actual Databricks job execution
- Deployment output capture and verification
- Comprehensive error handling and logging

### Usage
```yaml
# Configure pipeline variables
variables:
  - group: databricks-secrets
  - name: resourceGroupName
    value: 'rg-databricks-infrastructure'
  - name: location
    value: 'East US'
```

## Migration from ARM Custom Resource Provider

The implementation supports both direct API calls and ARM Custom Resource Provider patterns:

1. **Direct API Approach**: Uses Azure Deployment Scripts with PowerShell (recommended)
2. **Custom Provider Approach**: Available in `databricks-infrastructure.bicep` for enterprise scenarios
3. **Hybrid Deployments**: Mix both approaches based on requirements
4. **Migration Path**: Gradual transition from custom providers to direct API calls

## Best Practices

### Security
- Always use Azure Key Vault for storing Databricks tokens
- Never hardcode sensitive values in templates
- Use managed identities where possible for Azure resource access
- Implement proper RBAC for deployment permissions

### Resource Management
- Use consistent naming conventions across all resources
- Apply comprehensive tagging for cost tracking and governance
- Implement proper lifecycle management with auto-termination settings
- Monitor resource utilization and optimize configurations

### Performance
- Use instance pools for cost-effective compute resource sharing
- Configure auto-scaling based on actual workload patterns
- Enable Photon runtime for improved performance where applicable
- Optimize Spark configurations for your specific use cases

### Monitoring and Alerting
- Set up email notifications for job failures
- Monitor cluster utilization and costs
- Implement alerting for long-running or failed deployments
- Use Azure Monitor for deployment script execution tracking

## Troubleshooting

### Common Issues

1. **Authentication Failures**
   ```
   Error: Databricks API call failed: Unauthorized (Status: 401)
   ```
   - Verify Databricks token is valid and not expired
   - Check token permissions for the required operations
   - Ensure workspace URL is correct and accessible

2. **Resource Creation Timeouts**
   ```
   Error: Cluster creation timed out after 30 attempts
   ```
   - Check Databricks workspace capacity and quotas
   - Verify node types are available in the workspace region
   - Review cluster configuration for invalid settings

3. **Parameter Validation Errors**
   ```
   Error: The template parameter 'NodeTypeId' is not valid
   ```
   - Verify parameter values match Databricks API requirements
   - Check for typos in node type IDs or other identifiers
   - Ensure required parameters are provided

### Debugging Deployment Scripts

1. **View Script Logs**: Check the deployment script execution logs in Azure portal
2. **Enable Verbose Logging**: Add `Write-Host` statements for debugging
3. **Test API Calls**: Use the `Invoke-DatabricksApi` helper directly for testing
4. **Validate JSON**: Ensure configuration objects are properly formatted

### Getting Help

- **Databricks API Documentation**: https://docs.databricks.com/dev-tools/api/latest/
- **Azure Deployment Scripts**: https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/deployment-script-template
- **Bicep Documentation**: https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/

## Contributing

Contributions are welcome! Please:

1. Follow the established coding standards and patterns
2. Include comprehensive tests for new modules
3. Update documentation with usage examples
4. Ensure all CI checks pass before submitting PRs
5. Keep PRs focused and under 600 lines of changes

## Implementation Status

### Phase 1 - Completed ✅
- ✅ Core infrastructure modules (cluster, instance-pool, job)
- ✅ Centralized API helper (`Invoke-DatabricksApi.ps1`)
- ✅ Comprehensive testing framework (94 Pester test files)
- ✅ Complete workspace deployment example

### Phase 2 - Completed ✅
- ✅ Workspace configuration modules (8 workspace-related modules)
- ✅ Security and permissions modules (10 permission-related modules)
- ✅ Data source and mount point modules (file, dbfs-file, directory, mount, volume)
- ✅ Advanced job types and workflows (job, pipeline modules)

### Phase 3 - Completed ✅
- ✅ 94 Terraform resource equivalents implemented
- ✅ Advanced features (Unity Catalog with 9 modules, MLflow with 5 modules)
- ✅ CI/CD integration with Azure DevOps pipeline
- ✅ Multi-workspace deployment patterns (MWS modules)

### Additional Achievements ✅
- ✅ Vector search capabilities (vector-search-endpoint, vector-search-index)
- ✅ Data quality monitoring (quality-monitor, lakehouse-monitor)
- ✅ Enhanced security features (compliance profiles, enhanced monitoring)
- ✅ Delta sharing (share, recipient modules)
- ✅ Complete governance framework (policies, access control, budgets)

## License

This project is licensed under the MIT License - see the LICENSE file for details.
