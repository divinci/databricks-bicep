BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
}

Describe "Databricks MLflow Experiment Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic MLflow experiment" {
            $templateFile = "$PSScriptRoot/../modules/mlflow-experiment.bicep"
            $parameters = @{
                ExperimentName = "/Shared/test-experiment-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ExperimentId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.ExperimentName.Value | Should -Be $parameters.ExperimentName
            $deployment.Outputs.LifecycleStage.Value | Should -Be "active"
            $deployment.Outputs.CreationTime.Value | Should -BeGreaterThan 0
            $deployment.Outputs.LastUpdateTime.Value | Should -BeGreaterThan 0
            
            $script:CreatedExperimentId = $deployment.Outputs.ExperimentId.Value
        }
        
        It "Should create an MLflow experiment with custom artifact location" {
            $templateFile = "$PSScriptRoot/../modules/mlflow-experiment.bicep"
            $parameters = @{
                ExperimentName = "/Shared/test-custom-experiment-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ArtifactLocation = "dbfs:/databricks/mlflow-tracking/$(Get-Random)"
                Tags = @{
                    "environment" = "test"
                    "team" = "data-science"
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ArtifactLocation.Value | Should -Be $parameters.ArtifactLocation
            
            $script:CreatedCustomExperimentId = $deployment.Outputs.ExperimentId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty experiment name" {
            $templateFile = "$PSScriptRoot/../modules/mlflow-experiment.bicep"
            $parameters = @{
                ExperimentName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
            }
            
            { 
                New-AzResourceGroupDeployment `
                    -ResourceGroupName $script:TestResourceGroup `
                    -TemplateFile $templateFile `
                    -TemplateParameterObject $parameters `
                    -Mode Incremental `
                    -ErrorAction Stop
            } | Should -Throw
        }
    }
}

AfterAll {
    if ($script:CreatedExperimentId) {
        Write-Host "Cleaning up MLflow experiment: $($script:CreatedExperimentId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $deleteBody = @{
                experiment_id = $script:CreatedExperimentId
            } | ConvertTo-Json
            
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/mlflow/experiments/delete" `
                -Body $deleteBody `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup MLflow experiment $($script:CreatedExperimentId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedCustomExperimentId) {
        Write-Host "Cleaning up custom MLflow experiment: $($script:CreatedCustomExperimentId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $deleteBody = @{
                experiment_id = $script:CreatedCustomExperimentId
            } | ConvertTo-Json
            
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/mlflow/experiments/delete" `
                -Body $deleteBody `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup custom MLflow experiment $($script:CreatedCustomExperimentId): $($_.Exception.Message)"
        }
    }
}
