#!/bin/bash
#
# Generate generate / request a  set of temporary AWS IAM Credentials, and save them to an aws cli profile.

set -e

check_deps() {
    
    # Checks script dependencies are installed
    # Parameters / Arguments: None

    if  ! command -v aws > /dev/null; then 
        echo "Unable to find path to AWS CLI (searching for 'aws'), Aborting." >&2 ; exit 127; 
    elif ! command -v jq > /dev/null; then
        echo "Unable to find path to 'jq', Aborting." >&2  ; exit 127; 
    
    elif ! command -v grep > /dev/null; then
        echo "Unable to find path to 'grep', Aborting." >&2 ; exit 127;
    fi
}

usage() {
    
    # Prints help to STDOUT, then exits with error code 1

    echo "Usage: $0 <-m | --mfa-token> MFA_TOKEN <-p | --profile> PROFILE [ -mp | --mfa-profile MFA_PROFILE ] [-r | --role <ROLE_ARN> <ROLE_SESSION_NAME> <ROLE_PROFILE> ]"
    echo "This script generates MFA credentials using the AWS CLI, and assigns them to a profile using aws configure."
    echo "Where:"
    echo "   MFA_TOKEN   = Code from virtual mfa device"
    echo "   PROFILE     = AWS CLI profile to use to generate temporary credentials, usually found in $HOME/.aws/config"
    echo "   MFA_PROFILE = AWS CLI profile to use (or create) to store temporary credentials."
    echo "   ROLE_ARN    = ARN of IAM role you would like to assume (Uses PROFILE to assume role)"
    echo "   ROLE_SESSION_NAME = Name of session name for IAM Role. See AWS Documentation for more info."
    echo "   ROLE_PROFILE = AWS CLI profile to use (or create) to store temporary role credentials."
    exit 1
}

check_args() {
    
    # Checks arguments passed to script are valid, and sets variables based on them
    # Required Arguments: $@

    if [ "$#" -eq 0 ]; then
        usage
    else
        # This variable is used as a counter for each the required parameters
        REQ_PARAM=0

        while [ "$#" -gt 0 ]; do
            key="$1"
            case $key in
                -m|--mfa-token)

                if [ -z "$2" ]; then
                    echo "Required argument MFA_TOKEN is missing." >&2
                    usage

                elif [ ! ${#2} -eq 6 ]; then
                    echo "MFA_TOKEN Appears to be shorter than 6 characters, Aborting." >&2
                    usage
                fi

                REQ_PARAM=$((REQ_PARAM + 1))
                MFA_TOKEN="$2"

                shift # past argument
                shift # past value
                ;;
                -p|--profile)
                if [ -z "$2" ]; then
                    echo "Required argument PROFILE is missing." >&2
                    usage
                
                elif  ! grep "$2" "$HOME/.aws/credentials" > /dev/null; then
                    echo "Unable to find profile $2 in ~/.aws/credentials, Aborting" >&2
                    exit 1
                fi 

                REQ_PARAM=$((REQ_PARAM + 1))
                PROFILE="$2"

                shift # past argument
                shift # past value
                ;;
                -mp|--mfa-profile)
                MFA_PROFILE="$2"

                shift # past argument
                shift # past value
                ;;
                -h|--help)
                usage
                shift
                ;;
                -r|--role)

                if [ -z "$2" ]; then
                    echo "Required argument ROLE_ARN is missing." >&2
                    usage
                elif [ -z "$3" ]; then
                    echo "Required Argument SESSION_NAME is missing." >&2
                    usage
                elif [ -z "$4" ]; then
                    echo "Required Argument ROLE_PROFILE is missing." >&2
                    usage
                fi

                ROLE_ARN="$2"
                SESSION_NAME="$3"
                ROLE_PROFILE="$4"
                ASSUME_ROLE=1

                shift 
                shift
                ;;
                *)    # Unknown parameter
                #usage
                shift # past argument
                ;;
            esac
        done

        if [ ! $REQ_PARAM = 2 ] && [ -z "$ASSUME_ROLE" ]; then
            echo "Required parameters missing, Aborting" >&2
            usage
        fi
    fi
}

check_config() {
    
    # Checks & Reads MFA Device Serial Number from script config file, and creates a config if one is not present.
    # Required Arguments / Parameters:
    # $PROFILE
    # Variables this function uses
    # MFA_ARN - ARN of MFA device
    # PROFILE - AWS CLI Profile to use

    if [ -z "$PROFILE" ]; then
        echo "Required argument PROFILE missing for check_config function. Printing value of PROFILE below." >&2
        echo "PROFILE: $PROFILE" >&2
    fi 

    # A role will never require a MFA device, therefore we do not need to make the API call to find out what one the user is using.
    if ! grep "$PROFILE" "$HOME/.mfa.cfg" && [ -z "$ASSUME_ROLE" ]; then
        echo "[INFO] No config found, creating config now."
        MFA_ARN=$(aws iam list-mfa-devices --profile "$PROFILE" | jq -r '.MFADevices[].SerialNumber')
        
        # Error Handling
        # Prevents us from trying to generate temporary credentials with an incorrect serial number & writing to the config with a bad serial number

        if [ ! "$MFA_ARN" ]; then
            echo "Failed to get ARN of MFA device. Please enter it in the config file with the following syntax" >&2
            echo "$PROFILE=MFA_ARN" >&2
            echo "To get the ARN of your MFA device, please run aws iam list-mfa-devices --profile $PROFILE | jq -r'.MFADevices[].SerialNumber'" >&2
            exit 1
        fi

        # There's a chance that the MFA token could have expired by the time we've made the API call
        # To get the users MFA Device & Written to the config file

        echo "$PROFILE=$MFA_ARN" >> "$HOME/.mfa.cfg"
        echo "[INFO] Config file created, please re run this script."
        exit 0 
    else

        MFA_ARN=$(grep "$PROFILE" "$HOME/.mfa.cfg" | cut -d '=' -f2 | tr -d '"')
        if [ ! "$MFA_ARN" ]; then
            echo "Unable to find MFA Device ARN in config file located at $HOME/.mfa.cfg" >&2
            echo "It is possible that the config syntax is incorrect or the file has incorrect permisions" >&2
            echo "Or it is empty." >&2

            # TODO: Check if config is empty, since it wouldn't have been written to so we can delete it if it is

            exit 1
        fi
    fi
}

generate_mfa_credentials() {
    
    # Generates AWS IAM Credentials ( aws sts get-session-token ) using an MFA device & MFA Token,
    # Then saves the newly generated credentials to an AWS CLI profile.
    # Required Arguments:
    # $PROFILE - AWS CLI Profile to use to run aws sts get-session-token
    # $MFA_ARN - ARN of MFA device 
    # $MFA_TOKEN - Token code from MFA device
    # Other Arguments:
    # $MFA_PROFILE - Profile to write IAM Credentials to
    
    if [ -z "$MFA_PROFILE" ]; then
        MFA_PROFILE="$PROFILE-mfa"
    fi

    if [ -z "$PROFILE" ] || [ -z "$MFA_ARN" ] || [ -z "$MFA_TOKEN" ]; then
        echo "Required arguments missing for generate_mfa_credentials function. Printing values of required arguments below." >&2
        echo "PROFILE: $PROFILE" >&2
        echo "MFA_ARN: $MFA_ARN" >&2
        echo "MFA_TOKEN: $MFA_TOKEN" >&2
        exit 1
    fi

    TEMP_CREDS=$(aws sts get-session-token --profile "$PROFILE" --serial-number "$MFA_ARN" --token-code "$MFA_TOKEN" --output json)
    
    if [ ! "$TEMP_CREDS" ] || [ -z "$TEMP_CREDS" ]; then
      echo "Generation of IAM credentials appears to have failed, as there was either a non-zero exit code or the variable TEMP_CREDS was null." >&2
      exit 1
    fi

    TEMP_ACCESS_KEY_ID=$(echo "$TEMP_CREDS" | jq -r '.[].AccessKeyId')
    TEMP_SECRET_KEY=$(echo "$TEMP_CREDS" | jq -reM '.[].SecretAccessKey')
    TEMP_SESSION_TOKEN=$(echo "$TEMP_CREDS" | jq -reM '.[].SessionToken')

    # We don't want to write to the config file if the values are null.
    # All values below are required so it doesn't matter which one is missing, just that one of them is.

    if [ -z "$TEMP_ACCESS_KEY_ID" ] || [ -z "$TEMP_SECRET_KEY" ] || [ -z "$TEMP_SESSION_TOKEN" ] || [ -z "$MFA_PROFILE" ]; then
      echo "Generation of AWS IAM credentails appears to have failed, priting values of variables related to IAM credential generation below." >&2
      echo "TEMP_ACCESS_KEY_ID: $TEMP_ACCESS_KEY_ID"
      echo "TEMP_SECRET_KEY: $TEMP_SECRET_KEY"
      echo "TEMP_SESSION_TOKEN: $TEMP_SESSION_TOKEN"
      echo "MFA_PROFILE: $MFA_PROFILE"
      exit 1
    fi

    echo "[INFO] Saving MFA credentials to AWS CLI profile $MFA_PROFILE"
    
    # TODO: Check if these are written before exiting.
    aws configure set aws_access_key_id "$TEMP_ACCESS_KEY_ID" --profile "$MFA_PROFILE"
    aws configure set aws_secret_access_key "$TEMP_SECRET_KEY" --profile "$MFA_PROFILE"
    aws configure set aws_session_token "$TEMP_SESSION_TOKEN" --profile "$MFA_PROFILE"
}

assume_role() {

    # Assumes an IAM role and writes credentials to an AWS CLI Profile.
    # Required Arguments:
    # $ROLE_ARN - ARN of IAM role to assume
    # $SESSION_NAME - Session name to pass to aws sts assume-role command
    # $PROFILE - AWS CLI Profile to use to assume the role
    # $ROLE_PROFILE - AWS CLI profile to write access keys to
    
    if [ -z "$ROLE_ARN" ] || [ -z "$SESSION_NAME" ] || [ -z "$PROFILE" ] || [ -z "$ROLE_PROFILE" ]; then
        echo "assume_role Function appears to have required variables unset. Printing variables below" >&2
        echo "ROLE_ARN: $ROLE_ARN" >&2
        echo "ROLE_PROFILE: $ROLE_PROFILE" >&2
        echo "SESSION_NAME: $SESSION_NAME" >&2
        echo "PROFILE: $PROFILE" >&2
        exit 1
    fi

    ROLE_CREDS=$(aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name "$SESSION_NAME" --profile "$PROFILE" --output json)
    
    if [ ! "$ROLE_CREDS" ] || [ -z "$ROLE_CREDS" ]; then
      echo "Unable to assume IAM role, exiting. (aws sts assume-role command had a non-zero exit code, or the variable ROLE_CREDS is null)" >&2
      exit 1
    fi

    ROLE_ACCESS_KEY_ID=$(echo "$ROLE_CREDS" | jq -reM '.Credentials.AccessKeyId')
    ROLE_SECRET_KEY=$(echo "$ROLE_CREDS" | jq -reM '.Credentials.SecretAccessKey')
    ROLE_SESSION_TOKEN=$(echo "$ROLE_CREDS" | jq -reM '.Credentials.SessionToken')

    # Don't want to write to the config file if the values are null.

    if [ -z "$ROLE_ACCESS_KEY_ID" ] || [ ! "$ROLE_ACCESS_KEY_ID" ]; then
      echo "Secret Access Key ID variable is NULL, or ROLE_ACCESS_KEY_ID variable had a non-zero exit code." >&2
      echo "Assumption of IAM Role appears to have failed. Aborting." >&2
      exit 1
    fi

    if [ -z "$ROLE_SECRET_KEY" ] || [ ! "$ROLE_SECRET_KEY" ]; then
      echo "Secret Access Key variable is null, or the command had an non-zero exit code." >&2
      echo "Assumption of IAM Role appears to have failed. Aborting." >&2
      exit 1
    fi

    if [ -z "$ROLE_SESSION_TOKEN" ] || [ ! "$ROLE_SESSION_TOKEN" ]; then
      echo "Session Token variable is NULL or ROLE_SESSION_TOKEN had a non-zero exit code." >&2
      echo "Assumption of IAM Role appears to have failed. Aborting." >&2
      exit 1
    fi

    echo "Saving MFA credentials to AWS CLI profile $ROLE_PROFILE"
    
    
    # TODO: Validate if these are setting correctly before exiting.
    aws configure set aws_access_key_id "$ROLE_ACCESS_KEY_ID" --profile "$ROLE_PROFILE"
    aws configure set aws_secret_access_key "$ROLE_SECRET_KEY" --profile "$ROLE_PROFILE"
    aws configure set aws_session_token "$ROLE_SESSION_TOKEN" --profile "$ROLE_PROFILE"

}
check_deps
check_args "$@"
check_config

if [ ! -z "$MFA_TOKEN" ]; then
    generate_mfa_credentials    

elif [ $ASSUME_ROLE -eq 1 ]; then
    assume_role
fi
