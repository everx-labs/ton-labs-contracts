all: Budget.tvc MultiBallot.tvc ProposalRoot.tvc SuperRoot.tvc SMVStats.tvc TestSMVStats.tvc Contest.tvc

Budget.tvc: Budget.cpp Budget.hpp config.hpp
	clang -o Budget.tvc Budget.cpp

MultiBallot.tvc: MultiBallot.cpp MultiBallot.hpp DePool.hpp ProposalRoot.hpp config.hpp
	clang -o MultiBallot.tvc MultiBallot.cpp

ProposalRoot.tvc: ProposalRoot.cpp MultiBallot.hpp DePool.hpp ProposalRoot.hpp SuperRoot.hpp Budget.hpp config.hpp
	clang -o ProposalRoot.tvc ProposalRoot.cpp

SuperRoot.tvc: SuperRoot.cpp MultiBallot.hpp DePool.hpp ProposalRoot.hpp SuperRoot.hpp Budget.hpp config.hpp
	clang -o SuperRoot.tvc SuperRoot.cpp

SMVStats.tvc: SMVStats.cpp SMVStats.hpp config.hpp
	clang -o SMVStats.tvc SMVStats.cpp

Contest.tvc: Contest.cpp ProposalRoot.hpp MultiBallot.hpp config.hpp
	clang -o Contest.tvc Contest.cpp

