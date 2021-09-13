# codespaces-precache
Experimental feature. A limited number of organizations/repositories will be admitted into a closed private beta. You can learn more and ask to sign up for the private preview [here](https://docs.github.com/en/codespaces/customizing-your-codespace/prebuilding-codespaces-for-your-project). 

## Prerequisites

Your organization must have been granted access to this experimental feature in order to use this action.

## Step 1: Set up access token

In order to use this action, you will need to create a valid access token and set it in your [codespace repository secrets](https://docs.github.com/en/codespaces/managing-your-codespaces/managing-encrypted-secrets-for-your-codespaces) under the name `EXPERIMENTAL_CODESPACE_CACHE_TOKEN`. The token will need access to your target repository for precached codespaces.

### Step 1a: Generate access token
The token can be generated for any user. However, we highly recommend using a bot user with permission only to your target repository, or creating a new user and granting them permission to the target repository. This is because the access token `repo` permission grants access to all repositories the user has access to.

Once you have a target user with narrowly-scoped repository permissions, [Create a personal access token](https://docs.github.com/en/github/authenticating-to-github/keeping-your-account-and-data-secure/creating-a-personal-access-token) with only the `repo` permission selected.

![Screen Shot 2021-08-10 at 12 55 25 PM](https://user-images.githubusercontent.com/5428933/128901649-948606a0-a68e-46a1-910d-03be4c6834fc.png)

### Step 1b: Add the access token as a repository secret

[Create a repository secret](https://docs.github.com/en/actions/reference/encrypted-secrets#creating-encrypted-secrets-for-a-repository). In repository settings, under the Secrets tab and Codespaces sub-menu option, create a secret with a name of `EXPERIMENTAL_CODESPACE_CACHE_TOKEN` and a value of the token you just created. This secret value will be used in the precaching process to set up your precached codespaces. The url to create the secret is `https://github.com/[organization name]/[repository name]/settings/secrets/codespaces/new`.

<img width="1238" alt="Adding EXPERIMENTAL_CODESPACE_CACHE_TOKEN to repository codespaces secrets" src="https://user-images.githubusercontent.com/4596845/129975552-9d562c9b-32d1-4126-87e0-41f38af2bfe8.png">

## Step 2: Create the workflow file

[Create a workflow file](https://docs.github.com/en/actions/reference/workflow-syntax-for-github-actions) in your repo that uses the `github/codespaces-precache` action.

### Properties

#### Environment properties
The `GITHUB_TOKEN` variable needs to be added in the `env` to use this action. `GITHUB_TOKEN` is a token automatically generated by GitHub to authenticate the action. [Read more about `GITHUB_TOKEN` here](https://docs.github.com/en/actions/reference/authentication-in-a-workflow#about-the-github_token-secret).
```
env:
  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

#### Input properties
The following properties can be added as input properties using [jobs.<job_id>.steps[*].with](https://docs.github.com/en/actions/reference/workflow-syntax-for-github-actions#jobsjob_idstepswith)

| name | required? | description
-------|-----------|------------
|`regions` | yes | Separated region(s) to create cached codespaces in. Multiple regions can be specified, separated by spaces. Valid regions are: `WestUs2` `EastUs` `WestEurope` `SouthEastAsia`|
|`sku_name` | yes | Machine type for the cached codespaces. Example: `standardLinux32gb`|

##### Valid Sku names

|Cores | Sku name
-------|--------
|2-core |	basicLinux32gb|
|4-core	| standardLinux32gb|
|8-core	| premiumLinux|
|16-core | largePremiumLinux*|
|32-core | xLargePremiumLinux*|

*_Contact us to get access_

See [sku pricing info for more](https://docs.github.com/en/billing/managing-billing-for-github-codespaces/about-billing-for-codespaces#codespaces-pricing).

##### Other input properties
There are 2 additional input parameters for GitHub Codespaces developer use only: `target` and `target_url`. Access is required to use these parameters.

### Standard Template

```yml
name: precache codespace
on:
  push:
    branches:
      - main
  workflow_dispatch:
jobs:
  createPrebuild:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: github/codespaces-precache@v1.0.1
        with:
          regions: WestUs2
          sku_name: standardLinux32gb
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Troubleshooting

### I set up the action, how do I know if it worked?

Check the action logs for an error message or a success response with a state of 'pending' - this means the prebuild is being set up. It may take some time to set up the first time, so wait a few minutes and try creating a codespace to see if it is created from a prebuild.

#### Action failure looks like:

![Screen Shot 2021-08-26 at 12 54 37 PM](https://user-images.githubusercontent.com/5428933/131005400-68daaa3b-7a28-4d8e-bfa1-c22fbcb21170.png)

#### Action success response looks like:

![Screen Shot 2021-08-26 at 11 54 33 AM](https://user-images.githubusercontent.com/5428933/131005421-e1292e23-095b-4eee-9839-ebec31924b07.png)

### How do I know if my new codespace was created from a prebuild?
There's an environment value set when you first create the codespace. You can paste this command into the built-in terminal:
```
$ cat /workspaces/.codespaces/shared/environment-variables.json | jq '.ACTION_NAME'
"createFromPrebuild"
```
If the output is `"createFromPrebuild"` it was newly created from a prebuild.
