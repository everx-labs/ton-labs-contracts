# Creating secure environment with Tails OS and TONOS-CLI
Here is how you can create a secure environment with TONOS-CLI using a Tails OS USB drive:

1. Install the Tails image to a USB drive. Follow the steps listed here: [https://tails.boum.org/install/index.en.html](https://tails.boum.org/install/index.en.html)

2. When done, boot from the USB drive: connect the USB drive to your PC and reboot it.

3. Set up boot from USB in BIOS/UEFI.

4. Boot Tails.

5. To connect to the Internet, click network icon in the upper right corner.

- If you have wired connection, autoconnect through DHCP
- If you have wireless connection, configure it by entering your Wi-Fi SSID and password

6. Open **TOR** browser.

7. Go to TONOS-CLI Github page by manually entering the URL [https://github.com/tonlabs/tonos-cli](https://github.com/tonlabs/tonos-cli) in the the address bar of the TOR browser. On the GitHub page click on **release.**

8. Download the TONOS-CLI archive by clicking on the *.tar.gz filename under **Assets.**

9. Save the file and then open its location by clicking on the folder icon in the **Downloads** menu.

10. Extract TONOS-CLI utility:

10.1. double-click on the downloaded file and select **tonos-cli** binary. Then click **Extract**.

10.2. select **Home** folder from the left list and press the blue **Extract** button.

11. Download compiled multisignature contract and multisignature ABI file from [https://github.com/tonlabs/ton-labs-contracts/tree/master/solidity/safemultisig](https://github.com/tonlabs/ton-labs-contracts/tree/master/solidity/safemultisig). To go to the contracts URL, you may manually enter the URL in the TOR browser or navigate to the contracts repository in the TON Labs github (back to **tonlabs** → **ton-labs-contracts** → **solidity**/**safemultisig**).

You need to download two files: **SafeMultisigWallet.abi.json** and **SafeMultisigWallet.tvc** and place them next to the TONOS-CLI utility:

11.1. click on their names and choose **Save Link as.** Save both files.

11.2. move both downloaded files next to the TONOS-CLI utility: open the folder they are saved to by clicking on the folder icon in the **Downloads** menu; select both files, right click and select **Move to**; choose **Home** as the destination and confirm.


12. To work with TONOS-CLI you need to run the **Terminal** from the **Applications** menu.

