// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface INPairPool_in {
    function numberListedPairs() external view returns (uint256);
    function pairListed(uint256 _id) external view returns(address srcToken, uint256 srcDecimals, address destToken, uint256 destDecimals);
}

interface INPairPool_V2in {
    function numberListedPairs() external view returns (uint256);
    function pairListed(uint256 _id) external view returns(address srcToken, address destToken, uint typeAMM);
}

contract NPairPool_V2in is Ownable {

    struct pairStruct{
        address srcToken;
        uint256 srcDecimals;
        address destToken;
        uint256 destDecimals;
        uint typeAMM;
        bool active;
    }

    mapping (uint256 => pairStruct) private pairs;
    mapping (bytes32 => bool) private listedId;

    uint256 private totalPairs;

    event NewPairListed(uint256 indexed _id, address _srcToken, address _destToken, uint256 _timestamp);
    event PairLocked(uint256 indexed _id, uint256 _timestamp);
    event PairUnlocked(uint256 indexed _id, uint256 _timestamp);
    event PairModified(uint256 indexed _id, uint256 _timestamp);
    
    /* WRITE METHODS*/
    /*
    * @dev List new pair ot token
    * () will be defined the unit of measure
    * @param _srcToken token to be invested
    * @param _destToken token to be recived
    * @param _typeAMM type of AMM (0 = 1Inch, 1 = Paraswap)
    * @return bool successfully completed
    */
    function listNewPair(address _srcToken, address _destToken, uint _typeAMM) public onlyOwner returns(bool) {
        require(_srcToken != address(0) && _destToken != address(0), "NEON: null address not allowed");
        require(_srcToken != _destToken, "NEON: Source & Destination token must be different");
        bytes32 uniqueId = _getId(_srcToken, _destToken);
        require(!listedId[uniqueId], "NEON: Token pair already listed");
        pairs[totalPairs + 1].srcToken = _srcToken;
        pairs[totalPairs + 1].destToken = _destToken;
        pairs[totalPairs + 1].srcDecimals = ERC20(_srcToken).decimals();
        pairs[totalPairs + 1].destDecimals = ERC20(_destToken).decimals();
        pairs[totalPairs + 1].typeAMM = _typeAMM;
        pairs[totalPairs + 1].active = true;
        listedId[uniqueId] = true;
        totalPairs += 1;
        emit NewPairListed(totalPairs, _srcToken, _destToken, block.timestamp);
        return true;
    }
    /*
    * @dev Modify pair
    * () will be defined the unit of measure
    * @param _id of the pair to be locked
    * @param _srcToken parameter to be modified, if 0 will be ignored
    * @param _destToken parameter to be modified, if 0 will be ignored
    * @param _typeAMM type of AMM (0 = 1Inch, 1 = Paraswap), if 0 will be ignored
    */
    function modifyPair(
        uint256 _id,
        address _srcToken,
        address _destToken,
        uint _typeAMM
        ) external onlyOwner {

        require(_id > 0, "NEON: ID must be > 0");
        require(_id <= totalPairs, "NEON: ID out of range");
        pairStruct storage pair = pairs[_id];
        if(_srcToken != address(0)){
            pair.srcToken = _srcToken;
            pair.srcDecimals = ERC20(_srcToken).decimals();
        }
        if(_destToken != address(0)){
            pair.destToken = _destToken;
            pair.destDecimals = ERC20(_destToken).decimals();            
        }
        pair.typeAMM = _typeAMM != 0 ? _typeAMM : pair.typeAMM;
        emit PairModified(_id, block.timestamp);
    }
    /*
    * @dev Blacklist a pair
    * () will be defined the unit of measure
    * @param _id of the pair to be locked
    */
    function lockPair(uint256 _id) external onlyOwner {
        require(_id > 0, "NEON: ID must be > 0");
        require(_id <= totalPairs, "NEON: ID out of range");

        pairStruct storage pair = pairs[_id];

        require(pair.active, "NEON: Pair already locked");

        pair.active = false;
        emit PairLocked(_id, block.timestamp);
    }
    /*
    * @dev Unlock a pair
    * () will be defined the unit of measure
    * @param _id of the pair to be unlocked
    */
    function unlockPair(uint256 _id) external onlyOwner {
        require(_id > 0, "NEON: ID must be > 0");
        require(_id <= totalPairs, "NEON: ID out of range");

        pairStruct storage pair = pairs[_id];

        require(!pair.active, "NEON: Pair already unlocked");

        pair.active = true;
        emit PairUnlocked(_id, block.timestamp);
    }
    /*
    * @dev download pair list from another NEON pool V1
    * () will be defined the unit of measure
    * @param _contract address of the old pool where pair list will be downloaded
    */
    function downloadPairList(address _contract) external onlyOwner {
        uint256 poolTotalPairs = INPairPool_in(_contract).numberListedPairs();
        for(uint256 i=1; i<=poolTotalPairs; i++){
            (address srcToken, , address destToken, ) = INPairPool_in(_contract).pairListed(i);
            listNewPair(srcToken, destToken, 1);
        }
    }
    /*
    * @dev download pair list from another NEON pool V2
    * () will be defined the unit of measure
    * @param _contract address of the old pool where pair list will be downloaded
    */
    function downloadPairListV2(address _contract) external onlyOwner {
        uint256 poolTotalPairs = INPairPool_V2in(_contract).numberListedPairs();
        for(uint256 i=1; i<=poolTotalPairs; i++){
            (address srcToken, address destToken, uint typeAMM) = INPairPool_V2in(_contract).pairListed(i);
            listNewPair(srcToken, destToken, typeAMM);
        }
    }
    /* INTERNAL */
    function _getId(address _srcToken, address _destToken) private pure returns (bytes32){
        return keccak256(abi.encodePacked(_srcToken, _destToken));
    }
    /* VIEW METHODS */
    /*
    * @view Total Pairs listed
    * () will be defined the unit of measure
    * @return uint256 total listed pairs
    */
    function numberListedPairs() external view returns(uint256) {
        return totalPairs;
    }
    /*
    * @view pair listed address
    * () will be defined the unit of measure
    * @param _id of the pair
    * @return srcToken address source token
    * @return srcDecimals token decimals
    * @return destToken address destination token
    * @return destDecimals token decimals
    * @return typeAMM type of AMM (1 = Paraswap, 2 = 1Inch)
    */
    function pairListed(uint256 _id) external view returns(address srcToken, uint256 srcDecimals, address destToken, uint256 destDecimals, uint typeAMM) {
        require(_id > 0, "NEON: ID must be > 0");
        require(_id <= totalPairs, "NEON: ID out of range");
        if(pairs[_id].active){
            srcToken =  pairs[_id].srcToken;
            destToken =  pairs[_id].destToken;
            srcDecimals =  pairs[_id].srcDecimals;
            destDecimals =  pairs[_id].destDecimals;
            typeAMM =  pairs[_id].typeAMM;
        }
    }
}