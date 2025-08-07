BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create test catalog and schema first
    $script:TestCatalogName = "test_ext_model_catalog_$(Get-Random)"
    $script:TestSchemaName = "test_ext_model_schema_$(Get-Random)"
}

Describe "Databricks External Model Bicep Module Tests" {
    BeforeAll {
        # Create test catalog for external model
        Write-Host "Creating test catalog: $($script:TestCatalogName)"
        $catalogConfig = @{
            name = $script:TestCatalogName
            comment = "Test catalog for external model tests"
            isolation_mode = "OPEN"
        } | ConvertTo-Json -Depth 10
        
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $createResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.1/unity-catalog/catalogs" `
                -Body $catalogConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            Write-Host "Created test catalog: $($script:TestCatalogName)"
            
            # Create test schema
            Write-Host "Creating test schema: $($script:TestSchemaName)"
            $schemaConfig = @{
                name = $script:TestSchemaName
                catalog_name = $script:TestCatalogName
                comment = "Test schema for external model tests"
            } | ConvertTo-Json -Depth 10
            
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.1/unity-catalog/schemas" `
                -Body $schemaConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            Write-Host "Created test schema: $($script:TestSchemaName)"
        }
        catch {
            Write-Warning "Failed to create test catalog/schema: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should create an external model for chat completions" {
            if (-not $script:TestCatalogName -or -not $script:TestSchemaName) {
                Set-ItResult -Skipped -Because "Test catalog/schema creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/external-model.bicep"
            $parameters = @{
                ModelName = "test_chat_model_$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
                Task = "llm/v1/chat"
                Comment = "Test external chat model for Bicep module testing"
                Tags = @{
                    environment = "test"
                    model_type = "chat"
                    provider = "openai"
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ModelName.Value | Should -Be $parameters.ModelName
            $deployment.Outputs.FullName.Value | Should -Be "$($script:TestCatalogName).$($script:TestSchemaName).$($parameters.ModelName)"
            $deployment.Outputs.CatalogName.Value | Should -Be $script:TestCatalogName
            $deployment.Outputs.SchemaName.Value | Should -Be $script:TestSchemaName
            $deployment.Outputs.Task.Value | Should -Be "llm/v1/chat"
            $deployment.Outputs.Comment.Value | Should -Be $parameters.Comment
            $deployment.Outputs.Tags.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Owner.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterThan 0
            $deployment.Outputs.UpdatedAt.Value | Should -BeGreaterThan 0
            $deployment.Outputs.CreatedBy.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.UpdatedBy.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedChatModelFullName = $deployment.Outputs.FullName.Value
        }
        
        It "Should create an external model for embeddings" {
            if (-not $script:TestCatalogName -or -not $script:TestSchemaName) {
                Set-ItResult -Skipped -Because "Test catalog/schema creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/external-model.bicep"
            $parameters = @{
                ModelName = "test_embedding_model_$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
                Task = "llm/v1/embeddings"
                Comment = "Test external embedding model"
                Tags = @{
                    environment = "test"
                    model_type = "embeddings"
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Task.Value | Should -Be "llm/v1/embeddings"
            
            $script:CreatedEmbeddingModelFullName = $deployment.Outputs.FullName.Value
        }
        
        It "Should create an external model for completions" {
            if (-not $script:TestCatalogName -or -not $script:TestSchemaName) {
                Set-ItResult -Skipped -Because "Test catalog/schema creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/external-model.bicep"
            $parameters = @{
                ModelName = "test_completion_model_$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
                Task = "llm/v1/completions"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Task.Value | Should -Be "llm/v1/completions"
            $deployment.Outputs.Comment.Value | Should -Be ""
            
            $script:CreatedCompletionModelFullName = $deployment.Outputs.FullName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty model name" {
            $templateFile = "$PSScriptRoot/../modules/external-model.bicep"
            $parameters = @{
                ModelName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
                Task = "llm/v1/chat"
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
        
        It "Should fail with invalid task type" {
            $templateFile = "$PSScriptRoot/../modules/external-model.bicep"
            $parameters = @{
                ModelName = "test_model"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
                Task = "invalid/task"
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
    
    AfterAll {
        # Cleanup external models
        if ($script:CreatedChatModelFullName) {
            Write-Host "Cleaning up chat external model: $($script:CreatedChatModelFullName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/external-models/$($script:CreatedChatModelFullName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup chat external model $($script:CreatedChatModelFullName): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedEmbeddingModelFullName) {
            Write-Host "Cleaning up embedding external model: $($script:CreatedEmbeddingModelFullName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/external-models/$($script:CreatedEmbeddingModelFullName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup embedding external model $($script:CreatedEmbeddingModelFullName): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedCompletionModelFullName) {
            Write-Host "Cleaning up completion external model: $($script:CreatedCompletionModelFullName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/external-models/$($script:CreatedCompletionModelFullName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup completion external model $($script:CreatedCompletionModelFullName): $($_.Exception.Message)"
            }
        }
        
        # Cleanup test schema
        if ($script:TestSchemaName) {
            Write-Host "Cleaning up test schema: $($script:TestSchemaName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/schemas/$($script:TestCatalogName).$($script:TestSchemaName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test schema: $($_.Exception.Message)"
            }
        }
        
        # Cleanup test catalog
        if ($script:TestCatalogName) {
            Write-Host "Cleaning up test catalog: $($script:TestCatalogName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/catalogs/$($script:TestCatalogName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test catalog: $($_.Exception.Message)"
            }
        }
    }
}
