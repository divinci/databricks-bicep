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

Describe "Databricks File Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a Python file in workspace" {
            $templateFile = "$PSScriptRoot/../modules/file.bicep"
            $pythonContent = @"
# Test Python file
print("Hello from Databricks!")

def test_function():
    return "This is a test function"

if __name__ == "__main__":
    print(test_function())
"@
            $encodedContent = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pythonContent))
            
            $parameters = @{
                Path = "/Shared/test-files/test-python-$(Get-Random).py"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Content = $encodedContent
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Path.Value | Should -Be $parameters.Path
            $deployment.Outputs.ObjectType.Value | Should -Be "FILE"
            $deployment.Outputs.ObjectId.Value | Should -BeGreaterThan 0
            $deployment.Outputs.Language.Value | Should -Be "PYTHON"
            $deployment.Outputs.Size.Value | Should -BeGreaterThan 0
            $deployment.Outputs.ModifiedAt.Value | Should -BeGreaterThan 0
            
            $script:CreatedFilePath = $deployment.Outputs.Path.Value
        }
        
        It "Should create a SQL file in workspace" {
            $templateFile = "$PSScriptRoot/../modules/file.bicep"
            $sqlContent = @"
-- Test SQL file
SELECT 
    'Hello from Databricks SQL!' as greeting,
    current_timestamp() as created_at,
    1 + 1 as simple_math;

-- Test query with parameters
SELECT * FROM information_schema.tables LIMIT 10;
"@
            $encodedContent = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($sqlContent))
            
            $parameters = @{
                Path = "/Shared/test-files/test-sql-$(Get-Random).sql"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Content = $encodedContent
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Language.Value | Should -Be "SQL"
            
            $script:CreatedSqlFilePath = $deployment.Outputs.Path.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty file path" {
            $templateFile = "$PSScriptRoot/../modules/file.bicep"
            $parameters = @{
                Path = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Content = "dGVzdA=="  # base64 encoded "test"
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
        
        It "Should fail with empty content" {
            $templateFile = "$PSScriptRoot/../modules/file.bicep"
            $parameters = @{
                Path = "/Shared/test-empty-file.py"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Content = ""
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
        # Cleanup files
        if ($script:CreatedFilePath) {
            Write-Host "Cleaning up file: $($script:CreatedFilePath)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.0/workspace/delete" `
                    -Body (@{ path = $script:CreatedFilePath; recursive = $false } | ConvertTo-Json) `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup file $($script:CreatedFilePath): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedSqlFilePath) {
            Write-Host "Cleaning up SQL file: $($script:CreatedSqlFilePath)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.0/workspace/delete" `
                    -Body (@{ path = $script:CreatedSqlFilePath; recursive = $false } | ConvertTo-Json) `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup SQL file $($script:CreatedSqlFilePath): $($_.Exception.Message)"
            }
        }
    }
}
