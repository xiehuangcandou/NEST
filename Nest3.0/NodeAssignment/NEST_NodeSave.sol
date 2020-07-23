pragma solidity 0.5.10;

/**
 * @title 分配nest存储
 */
contract NEST_NodeSave {
    
    IBMapping mappingContract;                      //  映射合约
    IBNEST nestContract;                            //  NEST合约
    
    /**
    * @dev 初始化方法
    * @param map 投票合约地址
    */
    constructor (address map) public {
        mappingContract = IBMapping(address(map));              
        nestContract = IBNEST(address(mappingContract.checkAddress("nest")));            
    }
    
    /**
    * @dev 重置投票合约
    * @param map 投票合约地址
    */
    function changeMapping(address map) public onlyOwner {
        mappingContract = IBMapping(address(map));
        nestContract = IBNEST(address(mappingContract.checkAddress("nest")));
    }
    
    // 转出nest
    function turnOut(uint256 amount, address to) public onlyMiningCalculation returns(uint256) {
        uint256 leftNum = nestContract.balanceOf(address(this));
        if (leftNum >= amount) {
            nestContract.transfer(to, amount);
            return amount;
        } else {
            return 0;
        }
    }
    
    // 仅限管理员
    modifier onlyOwner(){
        require(mappingContract.checkOwners(msg.sender) == true);
        _;
    }
    // 仅限分配合约
    modifier onlyMiningCalculation(){
        require(address(mappingContract.checkAddress("nodeAssignment")) == msg.sender);
        _;
    }
    
}

// 映射合约
contract IBMapping {
    // 查询地址
    function checkAddress(string memory name) public view returns (address contractAddress);
    // 查看是否管理员
    function checkOwners(address man) public view returns (bool);
}

// NEST合约
contract IBNEST {
    function totalSupply() public view returns (uint supply);
    function balanceOf( address who ) public view returns (uint value);
    function allowance( address owner, address spender ) public view returns (uint _allowance);
    function transfer( address to, uint256 value) external;
    function transferFrom( address from, address to, uint value) public returns (bool ok);
    function approve( address spender, uint value ) public returns (bool ok);
    function balancesStart() public view returns(uint256);
    function balancesGetBool(uint256 num) public view returns(bool);
    function balancesGetNext(uint256 num) public view returns(uint256);
    function balancesGetValue(uint256 num) public view returns(address, uint256);
    event Transfer( address indexed from, address indexed to, uint value);
    event Approval( address indexed owner, address indexed spender, uint value);
}