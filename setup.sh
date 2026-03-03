#!/bin/bash
# This script sets up the custom reports for GnuCash

echo "Setting up the custom reports for GnuCash"
echo "----------------------------------------"

# List of reports to link and add to config-user.scm
reports=("transaction-extended.scm" "account-piecharts-extended.scm")

echo "Linking the files to the userdata directory"
GNC_USERDATA_DIR=$(gnucash --paths | grep GNC_USERDATA_DIR | awk '{print $2}')

echo "  GNC_USERDATA_DIR: $GNC_USERDATA_DIR"

for report in "${reports[@]}"; do
    if [ -f $GNC_USERDATA_DIR/$report ]; then
        echo "  $report already exists in GNC_USERDATA_DIR, removing the file"
        rm $GNC_USERDATA_DIR/$report
    fi
    echo "  Linking $report to GNC_USERDATA_DIR, creating a new link"
    ln -s "$(pwd)/$report" $GNC_USERDATA_DIR/$report
done

echo "Adding the loading lines to the config-user.scm file"
GNC_USERCONFIG_DIR=$(gnucash --paths | grep GNC_USERCONFIG_DIR | awk '{print $2}')
echo "  GNC_USERCONFIG_DIR: $GNC_USERCONFIG_DIR"

config_user_file="$GNC_USERCONFIG_DIR/config-user.scm"
echo "  config_user_file: $config_user_file"

if [ ! -f $config_user_file ]; then
    echo "  config-user.scm file does not exist"
    echo "  Creating the file"
    touch $config_user_file
fi

for report in "${reports[@]}"; do
    load_line="(load (gnc-build-userdata-path \"${report}\"))"
    # If the line does not exist, add it.
    if ! grep -qF "$load_line" "$config_user_file"; then
        echo "  $load_line" >> "$config_user_file"
        echo "  Added $report to $config_user_file"
    else
        echo "  $report already exists in config_user_file"
    fi
done

echo "----------------------------------------"
echo "Setup complete"
