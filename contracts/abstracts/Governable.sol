// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../interfaces/governance/IGovernable.sol";
import "../interfaces/governance/IGovernance.sol";

abstract contract Governable is IGovernable {
    using AddressUpgradeable for address;

    //== Variables ==
    address public override gov_contract; // contract governing the Token


    //== CONSTRUCTOR ==
    /**
     * @dev Initializes the contract setting the deployer as the initial Governor.
     */
    function initialize(address _gov_contract) internal virtual {
        require (_gov_contract.isContract(), "_gov_contract should be a contract");
        gov_contract = _gov_contract;
    }


    //== MODIFIERS ==
    modifier onlyMastermind() {
        require(IGovernance(gov_contract).isMastermind(msg.sender), "Only mastermind is allowed");
        _;
    }
    modifier onlyGovernor() {
        require(IGovernance(gov_contract).isGovernor(msg.sender), "Only governor is allowed");
        _;
    }
    modifier onlyPartner() {
        require(IGovernance(gov_contract).isPartner(msg.sender), "Only partner is allowed");
        _;
    }


    //== SET INTERNAL VARIABLES==
    /**
     * @dev Change the governance contract
     * only mastermind is allowed to do this
     * @param _gov_contract Governance contract address
     */
    function setGovernanceContract(address _gov_contract) external onlyMastermind {
        require(_gov_contract.isContract(), "_gov_contract should be a contract");
        gov_contract = _gov_contract;
    }
}