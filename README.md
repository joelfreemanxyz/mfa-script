mfa-script
==========

Bash script to generate temporary AWS IAM credentials with MFA and save them to an aws cli profile.

requirements
------------
- aws cli [installed & configured with a profile you would like to use]
- jq
- grep
- cut
- tr 
- make [optional]
  
All of these are available on windows via WSL or Git Bash / a similar tool.

what it does
-----------

This script does the following:
- generates temporary aws iam credentials using an mfa token, and writes them to an aws cli profile.
- optionally assumes an iam role, and writes the credentials to an aws cli profile.

getting started
---------------

To install the script, run `make` in this directory.
Alteratively, move the script to somewhere on your `$PATH` so it can be called from anywhere.

You should not have to create a config file manually. The script should do that automatically.

usage
-----

Generating temporary IAM credentials using an MFA device, and witing the credentials to a profile
- `./aws-mfa -m <token-code> -p <profile-to-use> -mp <profile-to-write-new-credentials-to>` 

Assuming an IAM role and writing the credentials to a profile
- `./aws-mfa -p <profile-to-use> -r <role-arn> <role-session-name> <profile-to-write-role-credentials-to>`

testing
-------

This script has the following dependencies for testing:
- make
- shellcheck 
- bats [bash automated testing system] (not currently required as there are no unit tests as of writing this.)

how to test:
- run `make test`

exit codes
----------

- 0: Script ran fine, no errors.
- 1: Script had an error & Exited.
- 127: Dependencies not present

to do
-----

- Add License file to Project
- Write Unit & Functional Tests
- Add update function to script
- Create CircleCI Pipeline for Project
