############################################################################
# List of steps to remove the rescue resource group rescueRG-JPNE-Services
############################################################################
# Step 0: Logs-in to Azure
Connect-AzAccount
# Step 1: Setting the context to SubscriptionID :deadbb95-9db5-472f-bda3-f6eecc3b3ff2
$authContext = Set-AzContext -Subscription deadbb95-9db5-472f-bda3-f6eecc3b3ff2
# Step 1: Removing the rescue resource Group rescueRG-JPNE-Services
$result = Remove-AzResourceGroup -Name rescueRG-JPNE-Services
