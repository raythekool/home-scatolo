@description('Azure region for all resources. Confirm the selected model is available in this region before deployment.')
param location string = resourceGroup().location

@description('Globally unique base name using lowercase letters and numbers only.')
@minLength(2)
param namePrefix string

@description('Model name available to the selected Azure AI Foundry project.')
param modelName string = 'gpt-4o'

@description('Exact model version approved by Azure AI Foundry quota in this region.')
param modelVersion string = ''

@description('Deployment name used by the recognition API.')
param modelDeploymentName string = 'home-scatolo-vision'

@description('Capacity for the Azure OpenAI standard deployment in thousands of tokens per minute.')
param modelCapacity int = 1

@description('Set true only after confirming model availability and quota in the chosen region.')
param deployModel bool = false

@description('Allowed browser origin for the public recognition API.')
param allowedOrigin string = 'https://raythekool.github.io'

var registryName = 'acr${namePrefix}'
var environmentName = 'cae-${namePrefix}'
var identityName = 'id-${namePrefix}-api'
var openAiName = 'oai-${namePrefix}'
var workspaceName = 'log-${namePrefix}'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: registryName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspace.properties.customerId
        sharedKey: workspace.listKeys().primarySharedKey
      }
    }
  }
}

resource openAi 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: openAiName
  location: location
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: openAiName
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
  }
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (deployModel) {
  parent: openAi
  name: modelDeploymentName
  sku: {
    name: 'Standard'
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
}

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: registry
  name: guid(registry.id, identity.id, 'AcrPull')
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  }
}

resource openAiUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: openAi
  name: guid(openAi.id, identity.id, 'CognitiveServicesOpenAIUser')
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  }
}

output allowedOrigins string = allowedOrigin
output containerAppsEnvironmentId string = containerAppsEnvironment.id
output containerRegistryLoginServer string = registry.properties.loginServer
output managedIdentityId string = identity.id
output openAiEndpoint string = 'https://${openAi.properties.customSubDomainName}.openai.azure.com'
output openAiModelDeployment string = modelDeploymentName