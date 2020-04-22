pragma solidity 0.6.0;

import "../Lib/SafeMath.sol";

/**
 * @title 价格合约
 * @dev 包含token价格的增加修改
 */
contract Nest_NToken_OfferPrice {
    using SafeMath for uint256;
    Nest_3_VoteFactory _voteFactory;                                //  投票合约
    address _offerMain;                                             //  报价工厂合约
    Nest_NToken_TokenMapping _tokenMapping;                         //  ntoken映射
    address _abonusAddress;                                         //  分红池
    struct Price {                                                  //  价格结构体
        uint256 ethAmount;                                          //  eth数量
        uint256 erc20Amount;                                        //  erc20数量
        uint256 blockNum;                                           //  上一个报价区块号、当前价格区块
        uint256 endBlock;                                           //  生效区块
    }
    struct AddressPrice {                                           //  token价格信息结构体
        mapping(uint256 => Price) tokenPrice;                       //  token价格,区块号 => 价格
        Price latestPrice;                                          //  最新价格
    }
    uint256 priceCost = 10 ether;                                   //  价格费用
    uint256 priceCostUser = 9;                                      //  价格费用用户比例
    uint256 priceCostAbonus = 1;                                    //  价格费用分红池比例
    mapping(address => bool) _blackList;                            //  黑名单
    mapping(uint256 => mapping(address => address)) blockAddress;   //  区块报价第一人
    mapping(address => AddressPrice) tokenInfo;                     //  token价格信息
    
    //  实时价格 toekn, eth数量,erc20数量
    event NowTokenPrice(address a, uint256 b, uint256 c);
    
    /**
    * @dev 初始化方法
    * @param voteFactory 投票合约地址
    */
    constructor (address voteFactory) public {
        _voteFactory = Nest_3_VoteFactory(address(voteFactory));
        _offerMain = address(_voteFactory.checkAddress("nest.nToken.offerMain"));
        _abonusAddress = address(_voteFactory.checkAddress("nest.v3.nTokenAbonus"));
        _tokenMapping = Nest_NToken_TokenMapping(address(_voteFactory.checkAddress("nest.nToken.tokenMapping")));
    }
    
    /**
    * @dev 修改投票合约
    * @param voteFactory 投票合约地址
    */
    function changeMapping(address voteFactory) public onlyOwner {
        _voteFactory = Nest_3_VoteFactory(address(voteFactory));                                                                   
        _offerMain = address(_voteFactory.checkAddress("nest.nToken.offerMain"));
        _abonusAddress = address(_voteFactory.checkAddress("nest.v3.nTokenAbonus"));
        _tokenMapping = Nest_NToken_TokenMapping(address(_voteFactory.checkAddress("nest.nToken.tokenMapping")));
    }
    
    /**
    * @dev 增加价格
    * @param ethAmount eth数量
    * @param tokenAmount erc20数量
    * @param endBlock 报价生效区块
    * @param tokenAddress erc20地址
    */
    function addPrice(uint256 ethAmount, uint256 tokenAmount, uint256 endBlock, address tokenAddress) public onlyFactory {
        uint256 frontBlockNum = tokenInfo[tokenAddress].latestPrice.blockNum;                                                       
        if (block.number == frontBlockNum) {
            //  同一个区块报价
            //  更新历史价格
            tokenInfo[tokenAddress].tokenPrice[block.number].ethAmount = tokenInfo[tokenAddress].tokenPrice[block.number].ethAmount.add(ethAmount);
            tokenInfo[tokenAddress].tokenPrice[block.number].erc20Amount = tokenInfo[tokenAddress].tokenPrice[block.number].erc20Amount.add(tokenAmount);
            //  有价格偏差 ，区块价格延长
            if (endBlock > tokenInfo[tokenAddress].latestPrice.endBlock) {
                tokenInfo[tokenAddress].tokenPrice[block.number].endBlock = endBlock;
            }
        } else {
            //  更新历史价格
            tokenInfo[tokenAddress].tokenPrice[block.number] = Price(ethAmount,tokenAmount,frontBlockNum, endBlock);
            //  更新最近报价区块
            tokenInfo[tokenAddress].latestPrice.blockNum = block.number;
        }
        //  更新最后一个报价矿工
        blockAddress[block.number][tokenAddress] = address(tx.origin);
    }
    
    /**
    * @dev 更新并查看最新价格
    * @param tokenAddress token地址 
    * @return ethAmount eth数量
    * @return erc20Amount erc20数量
    */
    function updateAndCheckPriceNow(address tokenAddress) public returns(uint256 ethAmount, uint256 erc20Amount) {
        require(_blackList[msg.sender] == false, "In blackList");

        uint256 priceBlock = tokenInfo[tokenAddress].latestPrice.blockNum;
        AddressPrice storage tokenPriceInfo = tokenInfo[tokenAddress];
        while(tokenPriceInfo.tokenPrice[priceBlock].endBlock >= block.number || tokenPriceInfo.tokenPrice[priceBlock].ethAmount == 0){
            //  结束区块大于或等于当前区块,被吃单,都继续找下一个
            priceBlock = tokenPriceInfo.tokenPrice[priceBlock].blockNum;
            if (priceBlock == 0) {
                break;
            }
        }
        Price memory priceInfo = tokenPriceInfo.tokenPrice[priceBlock];
        tokenInfo[tokenAddress].latestPrice.ethAmount = priceInfo.ethAmount;
        tokenInfo[tokenAddress].latestPrice.erc20Amount = priceInfo.erc20Amount;
        tokenInfo[tokenAddress].latestPrice.endBlock = priceInfo.endBlock;
        //  报价合约调用 及 用户调用 不收费
        if (msg.sender != tx.origin && msg.sender != address(_offerMain)) {
            //  收费
            IERC20 nToken = IERC20(address(_tokenMapping.checkTokenMapping(tokenAddress)));
            require(nToken.transferFrom(address(msg.sender), address(this), priceCost));
            require(nToken.transfer(address(_abonusAddress), priceCost.mul(priceCostAbonus).div(10)));
            require(nToken.transfer(address(blockAddress[priceBlock][tokenAddress]), priceCost.mul(priceCostAbonus).div(10)));
        }
        
        emit NowTokenPrice(tokenAddress,tokenPriceInfo.latestPrice.ethAmount, tokenPriceInfo.latestPrice.erc20Amount);
        return (tokenPriceInfo.latestPrice.ethAmount,tokenPriceInfo.latestPrice.erc20Amount);
    }
    
    /**
    * @dev 更新并查看生效价格列表
    * @param tokenAddress token地址
    * @param num 查询条数
    * @return uint256[] 价格列表
    */
    function updateAndCheckPriceList(address tokenAddress, uint256 num) public payable returns (uint256[] memory) {
        require(_blackList[msg.sender] == false, "In blackList");
        //  收费
        uint256 thisPay = uint256(1 ether).mul(num);
        if (thisPay < 10 ether) {
            thisPay = 10 ether;
        } else if (thisPay > 50 ether) {
            thisPay = 50 ether;
        }
        IERC20 nToken = IERC20(address(_tokenMapping.checkTokenMapping(tokenAddress)));
        require(nToken.transferFrom(address(msg.sender), address(this), priceCost));
        
        //  提取数据
        uint256 priceBlock = tokenInfo[tokenAddress].latestPrice.blockNum;
        uint256 length = num.mul(3);
        uint256 index = 0;
        uint256[] memory data = new uint256[](length);
        AddressPrice storage tokenPriceInfo = tokenInfo[tokenAddress];
        while(index < length){
            if (tokenPriceInfo.tokenPrice[priceBlock].endBlock >= block.number || tokenPriceInfo.tokenPrice[priceBlock].ethAmount == 0) {
                //  结束区块大于或等于当前区块 ，被吃单，都继续找下一个
                if (priceBlock == 0) {
                    break;
                }
            } else {
                //  增加返回数据
                data[index++] = tokenPriceInfo.tokenPrice[priceBlock].ethAmount;
                data[index++] = tokenPriceInfo.tokenPrice[priceBlock].erc20Amount;
                data[index++] = tokenPriceInfo.tokenPrice[priceBlock].blockNum;
            }
            priceBlock = tokenPriceInfo.tokenPrice[priceBlock].blockNum;
        }
        
        //  分配
        require(nToken.transfer(address(_abonusAddress), thisPay.mul(priceCostAbonus).div(10)));
        require(nToken.transfer(address(blockAddress[priceBlock][tokenAddress]), thisPay.mul(priceCostAbonus).div(10)));
        
        return data;
    }
    
    /**
    * @dev 吃单修改价格
    * @param ethAmount eth数量 
    * @param tokenAmount erc20数量
    * @param tokenAddress token地址 
    * @param blockNum 价格区块 
    */
    function changePrice(uint256 ethAmount, uint256 tokenAmount, address tokenAddress, uint256 blockNum) public onlyFactory {
        tokenInfo[tokenAddress].tokenPrice[blockNum].ethAmount = tokenInfo[tokenAddress].tokenPrice[blockNum].ethAmount.sub(ethAmount);
        tokenInfo[tokenAddress].tokenPrice[blockNum].erc20Amount = tokenInfo[tokenAddress].tokenPrice[blockNum].erc20Amount.sub(tokenAmount);
    }
    
    //  查看历史区块价格合约-用户
    function checkPriceForBlock(address tokenAddress, uint256 blockNum) public view returns (uint256 ethAmount, uint256 erc20Amount, uint256 frontBlock) {
        require(msg.sender == tx.origin, "It can't be a contract");
        return (tokenInfo[tokenAddress].tokenPrice[blockNum].ethAmount, tokenInfo[tokenAddress].tokenPrice[blockNum].erc20Amount,tokenInfo[tokenAddress].tokenPrice[blockNum].blockNum);
    } 
    
    //  查看实时价格-用户
    function checkPriceNow(address tokenAddress) public view returns (uint256 ethAmount, uint256 erc20Amount,uint256 frontBlock) {
        require(msg.sender == tx.origin, "It can't be a contract");
        return (tokenInfo[tokenAddress].latestPrice.ethAmount,tokenInfo[tokenAddress].latestPrice.erc20Amount,tokenInfo[tokenAddress].latestPrice.blockNum);
    }

    //  查看最近报价区块
    function checkLatestBlock(address token) public view returns(uint256) {
        return tokenInfo[token].latestPrice.blockNum;
    }
    
    //  修改获取价格费用
    function changePriceCost(uint256 amount) public onlyOwner {
        require(amount > 0, "Parameter needs to be greater than 0");
        priceCost = amount;
    }
    
    //  查看获取价格费用 
    function checkPriceCost() public view returns(uint256) {
        return priceCost;
    }
    
    //  修改价格费用分配比例
    function changePriceCostProportion(uint256 user, uint256 abonus) public onlyOwner {
        require(user.add(abonus) == 10, "Wrong expense allocation proportion");
        priceCostUser = user;
        priceCostAbonus = abonus;
    }
    
    //  查看地址是否在黑名单
    function checkBlackList(address add) public view returns(bool) {
        return _blackList[add];
    }
    
    //  修改黑名单
    function changeBlackList(address add, bool isBlack) public onlyOwner {
        _blackList[add] = isBlack;
    }
    
    //  查看价格费用分配比例
    function checkPriceCostProportion() public view returns(uint256 user, uint256 abonus) {
        return (priceCostUser, priceCostAbonus);
    }
    
    //  仅限工厂
    modifier onlyFactory(){
        require(msg.sender == address(_voteFactory.checkAddress("nest.nToken.offerMain")), "No authority");
        _;
    }
    
    //  仅限投票修改
    modifier onlyOwner(){
        require(_voteFactory.checkOwners(msg.sender) == true, "No authority");
        _;
    }
}

//  投票合约
interface Nest_3_VoteFactory {
    //  查询地址
	function checkAddress(string calldata name) external view returns (address contractAddress);
	//  查看是否管理员
	function checkOwners(address man) external view returns (bool);
}

//  ntoken映射合约
interface Nest_NToken_TokenMapping {
    function checkTokenMapping(address token) external view returns (address);
}

/**
 * @title ntoken合约
 * @dev 包含标准erc20方法，挖矿增发方法，挖矿数据
 */
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address who) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


