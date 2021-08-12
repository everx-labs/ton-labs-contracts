all: FlexWallet.tvc TONTokenWallet.tvc RootTokenContract.tvc Wrapper.tvc

FlexWallet.tvc: TONTokenWallet.cpp TONTokenWallet.hpp
	clang TONTokenWallet.cpp -DTIP3_ENABLE_LEND_OWNERSHIP -DTIP3_ENABLE_BURN -mtvm-refunc -o FlexWallet.tvc

TONTokenWallet.tvc: TONTokenWallet.cpp TONTokenWallet.hpp
	clang TONTokenWallet.cpp -DTIP3_ENABLE_EXTERNAL -DTIP3_ENABLE_ALLOWANCE -DTIP3_IMPROVED_TRANSFER -mtvm-refunc -o TONTokenWallet.tvc

RootTokenContract.tvc: RootTokenContract.cpp RootTokenContract.hpp TONTokenWallet.hpp
	clang RootTokenContract.cpp -DTIP3_ENABLE_EXTERNAL -DTIP3_ENABLE_ALLOWANCE -DTIP3_IMPROVED_TRANSFER -o RootTokenContract.tvc

Wrapper.tvc: Wrapper.cpp Wrapper.hpp TONTokenWallet.hpp
	clang Wrapper.cpp -o Wrapper.tvc -DTIP3_ENABLE_EXTERNAL -DTIP3_ENABLE_ALLOWANCE -DTIP3_IMPROVED_TRANSFER

clean:
	rm -rf *.tvc
	rm -rf *.abi

