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

Describe "Databricks Pipeline Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic Delta Live Tables pipeline" {
            $templateFile = "$PSScriptRoot/../modules/pipeline.bicep"
            $parameters = @{
                PipelineName = "test-basic-pipeline-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Libraries = @(
                    @{
                        notebook = @{
                            path = "/Shared/test-notebook"
                        }
                    }
                )
                Target = "test_database"
                Continuous = $false
                Development = $true
                Edition = "CORE"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.PipelineId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.PipelineName.Value | Should -Be $parameters.PipelineName
            
            $script:CreatedBasicPipelineId = $deployment.Outputs.PipelineId.Value
        }
        
        It "Should create an advanced pipeline with custom configuration" {
            $templateFile = "$PSScriptRoot/../modules/pipeline.bicep"
            $parameters = @{
                PipelineName = "test-advanced-pipeline-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Libraries = @(
                    @{
                        notebook = @{
                            path = "/Shared/advanced-notebook"
                        }
                    }
                )
                Configuration = @{
                    "spark.sql.adaptive.enabled" = "true"
                    "spark.sql.adaptive.coalescePartitions.enabled" = "true"
                }
                PhotonEnabled = $true
                Edition = "ADVANCED"
                Clusters = @(
                    @{
                        label = "default"
                        num_workers = 2
                        node_type_id = "Standard_DS3_v2"
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            
            $script:CreatedAdvancedPipelineId = $deployment.Outputs.PipelineId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty pipeline name" {
            $templateFile = "$PSScriptRoot/../modules/pipeline.bicep"
            $parameters = @{
                PipelineName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Libraries = @()
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
    if ($script:CreatedBasicPipelineId) {
        Write-Host "Cleaning up basic pipeline: $($script:CreatedBasicPipelineId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/pipelines/$($script:CreatedBasicPipelineId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup basic pipeline $($script:CreatedBasicPipelineId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedAdvancedPipelineId) {
        Write-Host "Cleaning up advanced pipeline: $($script:CreatedAdvancedPipelineId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/pipelines/$($script:CreatedAdvancedPipelineId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup advanced pipeline $($script:CreatedAdvancedPipelineId): $($_.Exception.Message)"
        }
    }
}
