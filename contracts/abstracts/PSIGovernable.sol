// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../interfaces/governance/IPSIGovernable.sol";
import "../interfaces/governance/IPSIGovernance.sol";
import "./Governable.sol";

abstract contract PSIGovernable is IPSIGovernable, Governable {

    function gasToken() public override view returns (address) {
        return IPSIGovernance(gov_contract).gasToken();
    }
    function enableGasPromotion() public override view returns (bool) {
        return IPSIGovernance(gov_contract).enableGasPromotion();
    }
    
    function router() public override view returns (address) {
        return IPSIGovernance(gov_contract).router();
    }
}