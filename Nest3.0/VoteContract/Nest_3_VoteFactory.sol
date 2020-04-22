pragma solidity 0.6.0;

import "../Lib/SafeMath.sol";

/**
 * @title 投票工厂+ 映射
 * @dev 创建与投票方法
 */
contract Nest_3_VoteFactory {
    
    uint256 _limitTime = 7 days;                                    //  投票时间
    uint256 _circulationProportion = 51;                            //  通过票数比例
    uint256 _NNProportion = 15;                                     //  守护者节点1500票 = 总流通量15%
    uint256 _NNUsedCreate = 100;                                    //  创建合约抵押 NN数量
    ERC20 _NNToken;                                                 //  守护者节点token地址
    mapping(string => address) private _contractAddress;            //  投票合约映射
	mapping(address => bool) _modifyAuthority;                      //  修改权限
	mapping(address => address) _myVote;                            //  我的投票

    event ContractAddress(address contractAddress);
    
    /**
    * @dev 初始化方法
    */
    constructor () public {
        _NNToken = ERC20(checkAddress("nestNode"));
        _modifyAuthority[msg.sender] = true;
    }
    
    /**
    * @dev 重置合约
    */
    function changeMapping() public onlyOwner {
        _NNToken = ERC20(checkAddress("nestNode"));
    }
    
    /**
    * @dev 创建投票合约
    * @param contractAddress 投票可执行合约地址
    */
    function createVote(address contractAddress) public {
        require(address(tx.origin) == address(msg.sender), "It can't be a contract");
        Nest_3_VoteContract newContract = new Nest_3_VoteContract(contractAddress);
        require(_NNToken.transferFrom(address(tx.origin), address(newContract), _NNUsedCreate), "Authorization transfer failed");
        addSuperMan(address(newContract));
        emit ContractAddress(address(newContract));
    }
    
    /**
    * @dev 使用 nest 投票
    * @param contractAddress 投票合约地址
    */
    function nestVote(address contractAddress) public {
        require(address(msg.sender) == address(tx.origin), "It can't be a contract");
        require(checkOwners(contractAddress) == true, "It's not a voting contract");
        if (_myVote[address(msg.sender)] != address(0x0)) {
            Nest_3_VoteContract frontContract = Nest_3_VoteContract(_myVote[address(msg.sender)]);
            require(frontContract.checkContractEffective(), "You have a vote in progress");
        }
        Nest_3_VoteContract newContract = Nest_3_VoteContract(contractAddress);
        newContract.nestVote();
        _myVote[address(tx.origin)] = contractAddress;
    }
    
    /**
    * @dev 超级节点投票
    * @param contractAddress 投票合约地址
    * @param amount 投票数量
    */
    function nestNodeVote(address contractAddress,uint256 amount) public {
        require(address(msg.sender) == address(tx.origin), "It can't be a contract");
        require(checkOwners(contractAddress) == true, "It's not a voting contract");
        Nest_3_VoteContract newContract = Nest_3_VoteContract(contractAddress);
        require(_NNToken.transferFrom(address(msg.sender), address(contractAddress), amount), "Authorization transfer failed");        
        newContract.nestNodeVote(amount);
    }
    
    /**
    * @dev 查看是否有正在参与的投票 
    * @param user 参与投票地址
    * @return bool 是否正在参与投票
    */
    function checkVoteNow(address user) public view returns(bool) {
        Nest_3_VoteContract vote = Nest_3_VoteContract(_myVote[user]);
        if (vote.checkContractEffective() || vote.checkPersonalAmount(user) == 0) {
            return true;
        }
        return false;
    }
    
    /**
    * @dev 查看我的投票
    * @param user 参与投票地址
    * @return address 最近参与的投票合约地址
    */
    function checkMyVote(address user) public view returns (address) {
        return _myVote[user];
    }
    
    /**
    * @dev 查看投票时间
    */
    function checkLimitTime() public view returns(uint256) {
        return _limitTime;
    }
    
    /**
    * @dev 查看通过投票比例
    */
    function checkCirculationProportion() public view returns(uint256) {
        return _circulationProportion;
    }
    
    /**
    * @dev 查看NN token对应票数比例
    */
    function checkNNProportion() public view returns(uint256){
        return _NNProportion;
    }
    
    /**
    * @dev 创建合约抵押 NN数量
    */
    function checkNNUsedCreate() public view returns(uint256) {
        return _NNUsedCreate;
    }
    
    /**
    * @dev 修改投票时间
    */
    function changeLimitTime(uint256 num) public onlyOwner {
        require(num > 0, "Parameter needs to be greater than 0");
        _limitTime = num;
    }
    
    /**
    * @dev 修改通过投票比例
    */
    function changeCirculationProportion(uint256 num) public onlyOwner {
        require(num > 0, "Parameter needs to be greater than 0");
        _circulationProportion = num;
    }
    
    /**
    * @dev 修改守护者节点票数比例
    */
    function changeNNProportion(uint256 num) public onlyOwner {
        _NNProportion = num;
    }
    
    /**
    * @dev 修改合约抵押 NN数量
    */
    function changeNNUsedCreate(uint256 num) public onlyOwner {
        _NNUsedCreate = num;
    }
    
    //  查询地址
	function checkAddress(string memory name) public view returns (address contractAddress) {
		return _contractAddress[name];
	}
	
    //  添加合约映射地址
	function addContractAddress(string memory name, address contractAddress) public onlyOwner{
		_contractAddress[name] = contractAddress;
	}
	
	//  增加管理地址
	function addSuperMan(address superMan) public onlyOwner{
	    _modifyAuthority[superMan] = true;
	}
	
	//  删除管理地址
	function deleteSuperMan(address superMan) public onlyOwner{
	    _modifyAuthority[superMan] = false;
	}
	
	//  查看是否管理员
	function checkOwners(address man) public view returns (bool){
	    return _modifyAuthority[man];
	}
    
    //  仅限管理员操作
    modifier onlyOwner(){
        require(checkOwners(msg.sender) == true, "No authority");
        _;
    }
}

/**
 * @title 投票合约
 */
contract Nest_3_VoteContract {
    using SafeMath for uint256;
    
    Nest_3_MiningSave _miningSave;                      //  矿池合约
    Nest_3_Implement _implementContract;                //  可执行合约
    Nest_3_NestSave _nestSave;                          //  锁仓合约 
    Nest_3_VoteFactory _voteFactory;                    //  投票工厂合约
    ERC20 _nestToken;                                   //  nestToken
    ERC20 _NNToken;                                     //  守护者节点
    address _implementAddress;                          //  执行地址
    address _destructionAddress;                        //  销毁合约地址
    address _creator;                                   //  合约创建者
    uint256 _createTime;                                //  创建时间
    uint256 _endTime;                                   //  结束时间
    uint256 _totalAmount;                               //  总投票数
    uint256 _circulation;                               //  通过票数
    uint256 _NNSingleVote;                              //  NN单份票数
    uint256 _destroyedNest = 0;                         //  已销毁 NEST
    bool _effective = false;                            //  是否生效
    mapping(address => uint256) _personalAmount;        //  个人投票数
    mapping(address => uint256) _personalNNAmount;      //  个人 NN 账本
    
     /**
    * @dev 初始化方法
    * @param contractAddress 可执行合约地址
    */
    constructor (address contractAddress) public {
        //  初始化
        _voteFactory = Nest_3_VoteFactory(address(msg.sender));
        _miningSave = Nest_3_MiningSave(_voteFactory.checkAddress("nest.v3.miningSave"));
        _nestSave = Nest_3_NestSave(_voteFactory.checkAddress("nest.v3.nestSave"));
        _nestToken = ERC20(_voteFactory.checkAddress("nest"));
        _NNToken = ERC20(_voteFactory.checkAddress("nestNode"));
        _implementContract = Nest_3_Implement(address(contractAddress));
        _implementAddress = address(contractAddress);
        _destructionAddress = address(_voteFactory.checkAddress("nest.v3.destruction"));
        _creator = address(tx.origin);
        _createTime = now;                                                               
        _endTime = _createTime.add(_voteFactory.checkLimitTime());
        _circulation = (uint256(10000000000 ether).sub(_miningSave.checkBalance()).sub(_nestToken.balanceOf(address(_destructionAddress)))).mul(_voteFactory.checkCirculationProportion()).div(100);
        uint256 NNProportion = _voteFactory.checkNNProportion();
        _NNSingleVote = (uint256(10000000000 ether).sub(_miningSave.checkBalance())).mul(NNProportion).div(150000);
    }
    
    /**
    * @dev  NEST投票
    */
    function nestVote() public onlyFactory {
        require(now <= _endTime, "Voting time exceeded");
        require(_effective == false, "Vote in force");
        require(_personalAmount[address(tx.origin)] == 0, "Have voted");                      
        uint256 amount = _nestSave.checkAmount(address(tx.origin));
        _personalAmount[address(tx.origin)] = amount;
        _totalAmount = _totalAmount.add(amount);
        ifEffective();
    }
    
     /**
    * @dev 超级节点投票
    * @param amount 超级节点投票数量
    */
    function nestNodeVote(uint256 amount) public onlyFactory{
        require(now <= _endTime, "Voting time exceeded");
        require(_effective == false, "Vote in force");
        _personalNNAmount[address(tx.origin)] = _personalNNAmount[address(tx.origin)].add(amount);
        _totalAmount = _totalAmount.add(amount.mul(_NNSingleVote));
        ifEffective();
    }
    
    /**
    * @dev NEST取消投票
    */
    function nestVoteCancel() public {
        require(address(msg.sender) == address(tx.origin), "It can't be a contract");
        require(now <= _endTime, "Voting time exceeded");
        require(_effective == false, "Vote in force");
        require(_personalAmount[address(msg.sender)] > 0, "No vote");                     
        _totalAmount = _totalAmount.sub(_personalAmount[address(msg.sender)]);
        _personalAmount[address(msg.sender)] = 0;
    }
    
    /**
    * @dev 超级节点取消投票/取回
    */
    function nestNodeVoteCancel() public {
        require(address(msg.sender) == address(tx.origin), "It can't be a contract");
        uint256 myNN = _personalNNAmount[address(msg.sender)];
        require(myNN > 0, "No vote");                   
        uint256 frontNest = _nestToken.balanceOf(address(this));
        require(_NNToken.transfer(address(msg.sender), myNN), "Transfer failure");
        uint256 nowNest = _nestToken.balanceOf(address(this));
        uint256 nestAmount = nowNest.sub(frontNest);
        _destroyedNest.add(nestAmount);
        require(_nestToken.transfer(address(_destructionAddress), nestAmount), "Transfer failure");
        if (_effective == false && now <= _endTime) {
            _totalAmount = _totalAmount.sub(myNN.mul(_NNSingleVote));
            _personalNNAmount[address(msg.sender)] = 0;
        }
    }
    
    /**
    * @dev 执行修改合约
    */
    function startChange() public {
        require(_effective && now <= _endTime, "Vote unenforceable");
        //  将执行合约加入管理集合
        _voteFactory.addSuperMan(address(_implementContract));
        //  执行
        _implementContract.doit();
        //  将执行合约删除
        _voteFactory.deleteSuperMan(address(_implementContract));
        //  销毁 NEST
        uint256 nestAmount = _nestToken.balanceOf(address(this));
        _destroyedNest = _destroyedNest.add(nestAmount);
        _nestToken.transfer(address(_destructionAddress), nestAmount);
        
    }
    
    /**
    * @dev 判断是否生效
    */
    function ifEffective() private {
        if (_totalAmount > _circulation) {
            _effective = true;
        }
    }
    
    /**
    * @dev 查看投票合约是否结束
    */
    function checkContractEffective() public view returns(bool) {
        if (_effective || now > _endTime) {
            return true;
        } 
        return false;
    }
    
    //  查看执行合约地址 
    function checkImplementAddress() public view returns(address) {
        return _implementAddress;
    }
    
    //  查看合约创建者
    function checkCreator() public view returns(address) {
        return _creator;
    }
    
    //  查看投票开始时间
    function checkCreateTime() public view returns(uint256) {
        return _createTime;
    }
    
    //  查看投票结束时间
    function checkEndTime() public view returns(uint256) {
        return _endTime;
    }
    
    //  查看当前总投票数
    function checkTotalAmount() public view returns(uint256) {
        return _totalAmount;
    }
    
    //  查看通过投票数
    function checkCirculation() public view returns(uint256) {
        return _circulation;
    }
    
    //  查看个人投票数
    function checkPersonalAmount(address user) public view returns(uint256) {
        return _personalAmount[user];
    }
    
    //  查看个人 NN 投票数
    function checkPersonalNNAmount(address user) public view returns(uint256) {
        return _personalNNAmount[user];
    }
    
    //  查看合约中准备销毁的nest
    function checkNestBalance() public view returns(uint256) {
        return _nestToken.balanceOf(address(this));
    }
    
    //  查看已经销毁NEST
    function checkDestroyedNest() public view returns(uint256) {
        return _destroyedNest;
    }
    
    //  查看合约是否生效
    function checkEffective() public view returns(bool) {
        return _effective;
    }
    
    //  仅限工厂合约
    modifier onlyFactory(){
        require(address(_voteFactory) == address(msg.sender), "No authority");
        _;
    }
    //  仅限创建者操作
    modifier onlyCreator(){
        require(address(msg.sender) == _creator, "No authority");
        _;
    }
    
}

interface Nest_3_Implement {
    //  执行
    function doit() external;
}

//  矿池合约
interface Nest_3_MiningSave {
    //  查询矿池余额
    function checkBalance() external view returns(uint256);
}

//  nest锁仓合约
interface Nest_3_NestSave {
    //  查看锁仓金额
    function checkAmount(address sender) external view returns(uint256);
}

interface ERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}