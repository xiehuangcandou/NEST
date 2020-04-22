pragma solidity 0.6.0;

import "./SafeMath.sol";
import "./AddressPayable.sol";

/**
 * @title 价格合约
 * @dev 价格查询与调用
 */
contract Nest_3_OfferPrice{
    using SafeMath for uint256;
    using address_make_payable for address;
    Nest_3_VoteFactory _voteFactory;                                //  投票合约
    address _offerMain;                                             //  报价工厂合约
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
    mapping(address => AddressPrice) tokenInfo;                     //  token价格信息
    uint256 priceCost = 0.01 ether;                                 //  价格费用
    uint256 priceCostUser = 2;                                      //  价格费用用户比例
    uint256 priceCostAbonus = 8;                                    //  价格费用分红池比例
    mapping(uint256 => mapping(address => address)) blockAddress;   //  区块报价第一人
    address _abonusAddress;                                         //  分红池
    mapping(address => bool) _blackList;                            //  黑名单
    
    //  实时价格 toekn, eth数量,erc20数量
    event NowTokenPrice(address a, uint256 b, uint256 c);
    
    /**
    * @dev 初始化方法
    * @param voteFactory 投票合约地址
    */
    constructor (address voteFactory) public {
        _voteFactory = Nest_3_VoteFactory(address(voteFactory));
        _offerMain = address(_voteFactory.checkAddress("nest.v3.offerMain"));
        _abonusAddress = address(_voteFactory.checkAddress("nest.v3.abonus"));
    }
    
    /**
    * @dev 修改投票射合约
    * @param voteFactory 投票合约地址
    */
    function changeMapping(address voteFactory) public onlyOwner {
        _voteFactory = Nest_3_VoteFactory(address(voteFactory));                                   
        _offerMain = address(_voteFactory.checkAddress("nest.v3.offerMain"));
        _abonusAddress = address(_voteFactory.checkAddress("nest.v3.abonus"));
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
            //  不同区块报价
            //  更新历史价格
            tokenInfo[tokenAddress].tokenPrice[block.number] = Price(ethAmount,tokenAmount,frontBlockNum, endBlock);
            //  更新最近报价区块
            tokenInfo[tokenAddress].latestPrice.blockNum = block.number;
        }
        //  更新最后一个报价矿工
        blockAddress[block.number][tokenAddress] = address(msg.sender);
    }
    
    /**
    * @dev 更新并查看最新价格
    * @param tokenAddress token地址 
    * @return ethAmount eth数量
    * @return erc20Amount erc20数量
    */
    function updateAndCheckPriceNow(address tokenAddress) public payable returns(uint256 ethAmount, uint256 erc20Amount) {
        require(_blackList[msg.sender] == false, "In blackList");
        //  报价合约调用及用户调用不收费
        if (msg.sender != tx.origin && msg.sender != address(_offerMain)) {
            require(msg.value == priceCost, "Price call charge error");
        }
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
        
        if (msg.value > 0) {
            repayEth(_abonusAddress, msg.value.mul(priceCostAbonus).div(10));
            repayEth(blockAddress[priceBlock][tokenAddress], msg.value.mul(priceCostUser).div(10));
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
        uint256 thisPay = uint256(1 ether).div(10000).mul(num);
        if (thisPay < 0.002 ether) {
            require(msg.value == 0.002 ether);
        } else if (thisPay > 0.01 ether) {
            require(msg.value == 0.01 ether);
        } else {
            require(msg.value == thisPay);
        }
        
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
        repayEth(_abonusAddress, msg.value.mul(priceCostAbonus).div(10));
        repayEth(blockAddress[priceBlock][tokenAddress], msg.value.mul(priceCostUser).div(10));
        
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
    
    //  转eth
    function repayEth(address accountAddress, uint256 asset) private {
        address payable addr = accountAddress.make_payable();
        addr.transfer(asset);
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
    
    //  查看价格费用分配比例
    function checkPriceCostProportion() public view returns(uint256 user, uint256 abonus) {
        return (priceCostUser, priceCostAbonus);
    }
    
    //  查看获取价格费用 
    function checkPriceCost() public view returns(uint256) {
        return priceCost;
    }
    
    //  查看地址是否在黑名单
    function checkBlackList(address add) public view returns(bool) {
        return _blackList[add];
    }
    
    //  修改价格费用分配比例
    function changePriceCostProportion(uint256 user, uint256 abonus) public onlyOwner {
        require(user.add(abonus) == 10, "Wrong expense allocation proportion");
        priceCostUser = user;
        priceCostAbonus = abonus;
    }
    
    //  修改获取价格费用
    function changePriceCost(uint256 amount) public onlyOwner {
        priceCost = amount;
    }
    
    //  修改黑名单
    function changeBlackList(address add, bool isBlack) public onlyOwner {
        _blackList[add] = isBlack;
    }
    
    //  仅限工厂
    modifier onlyFactory(){
        require(msg.sender == address(_voteFactory.checkAddress("nest.v3.offerMain")), "No authority");
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



