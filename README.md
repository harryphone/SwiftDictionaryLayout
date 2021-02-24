# 探索Swift中Dictionary的底层实现及原理

# 前言

`swift`字典的设计思路和数组还是有点像的，可以参考我前面写的[数组](https://juejin.cn/post/6931236309176418311)篇，因为这里会讲swift字典用到的`hash`原理，篇幅有限，将会弱化源码的阅读。

# `Dictionary`的内存探索

既然和`Array`设计思路相似，我们看下`Dictionary`的内存中放了些什么？

运行如下代码，在`print`处打下断点看下：
```swift
var dic = ["1": "Dog", "2": "Car", "3": "Apple", "4": "Cat"]
withUnsafePointer(to: &dic) {
    print($0)
}
print("end")
```

断点调试后可以看到：
![](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/be012cd77220408fb5c0092b6b20aca5~tplv-k3u1fbpfcp-watermark.image)
`Dictionary`存的貌似是个堆上的地址`0x000000010053eb40`，查看该地址后，发现果然和`Array`一样，是一个类结构[HeapObject](https://juejin.cn/post/6905708198796361736)。但其他除了一个`4`貌似是字典个数，字典的`key`和`value`一个都没有找到。

所以下面我们看下`key`和`value`存在哪里？以及在`swift`中字典的底层原理

# `Dictionary`结构
```swift
public struct Dictionary<Key: Hashable, Value> {
    /// The element type of a dictionary: a tuple containing an individual
    /// key-value pair.
    public typealias Element = (key: Key, value: Value)
    
    @usableFromInline
    internal var _variant: _Variant
    
    @inlinable
    internal init(_native: __owned _NativeDictionary<Key, Value>) {
        _variant = _Variant(native: _native)
    }
    
    #if _runtime(_ObjC)
    @inlinable
    internal init(_cocoa: __owned __CocoaDictionary) {
        _variant = _Variant(cocoa: _cocoa)
    }
    ...
}
```

源码中`Dictionary`只有一个属性`_variant`，他是`_Variant`类型的，继续看下`_Variant`类型的属性：
```swift
@usableFromInline
    internal var object: _BridgeStorage<__RawDictionaryStorage>
```
也只有一个，类型`_BridgeStorage`的初始化就是一个强转赋值，这个和`Array`那一样，所以得看传进来什么东西。我们回头看`Dictionary`的初始化方法，如果我们调用的是`swift`原生的初始化方法，那么会走`init(_native: __owned _NativeDictionary<Key, Value>)`方法，那么传给`_Variant`的就是`_NativeDictionary`，所以`swift`的`Dictionary`就是`_NativeDictionary`（同理，源码中看到，如果是OC的字典会变成`__CocoaDictionary`，我们这只探索`swift`的）

接下来我们看下`_NativeDictionary`的源码中定义：
```swift
internal struct _NativeDictionary<Key: Hashable, Value> {
    @usableFromInline
    internal typealias Element = (key: Key, value: Value)
    
    /// See this comments on __RawDictionaryStorage and its subclasses to
    /// understand why we store an untyped storage here.
    @usableFromInline
    internal var _storage: __RawDictionaryStorage
    
    /// Constructs an instance from the empty singleton.
    @inlinable
    internal init() {
        self._storage = __RawDictionaryStorage.empty
    }
    
    /// Constructs a dictionary adopting the given storage.
    @inlinable
    internal init(_ storage: __owned __RawDictionaryStorage) {
        self._storage = storage
    }
    
    @inlinable
    internal init(capacity: Int) {
        if capacity == 0 {
            self._storage = __RawDictionaryStorage.empty
        } else {
            self._storage = _DictionaryStorage<Key, Value>.allocate(capacity: capacity)
        }
    }
    ...
}
```
`_NativeDictionary`也是一个属性`_storage`，`__RawDictionaryStorage`类型的，估计你也猜到了，`__RawDictionaryStorage`是类类型的。

我们找下`__RawDictionaryStorage`的定义：
```swift
@_fixed_layout
@usableFromInline
@_objc_non_lazy_realization
internal class __RawDictionaryStorage: __SwiftNativeNSDictionary {
  // NOTE: The precise layout of this type is relied on in the runtime to
  // provide a statically allocated empty singleton.  See
  // stdlib/public/stubs/GlobalObjects.cpp for details.

  /// The current number of occupied entries in this dictionary.
  @usableFromInline
  @nonobjc
  internal final var _count: Int

  /// The maximum number of elements that can be inserted into this set without
  /// exceeding the hash table's maximum load factor.
  @usableFromInline
  @nonobjc
  internal final var _capacity: Int

  /// The scale of this dictionary. The number of buckets is 2 raised to the
  /// power of `scale`.
  @usableFromInline
  @nonobjc
  internal final var _scale: Int8

  /// The scale corresponding to the highest `reserveCapacity(_:)` call so far,
  /// or 0 if there were none. This may be used later to allow removals to
  /// resize storage.
  ///
  /// FIXME: <rdar://problem/18114559> Shrink storage on deletion
  @usableFromInline
  @nonobjc
  internal final var _reservedScale: Int8

  // Currently unused, set to zero.
  @nonobjc
  internal final var _extra: Int16

  /// A mutation count, enabling stricter index validation.
  @usableFromInline
  @nonobjc
  internal final var _age: Int32

  /// The hash seed used to hash elements in this dictionary instance.
  @usableFromInline
  internal final var _seed: Int

  /// A raw pointer to the start of the tail-allocated hash buffer holding keys.
  @usableFromInline
  @nonobjc
  internal final var _rawKeys: UnsafeMutableRawPointer

  /// A raw pointer to the start of the tail-allocated hash buffer holding
  /// values.
  @usableFromInline
  @nonobjc
  internal final var _rawValues: UnsafeMutableRawPointer
  
  ...
}
```
`__RawDictionaryStorage`的父类没有属性，所以整个`__RawDictionaryStorage`的属性就这么多了。这样我们把`Dictionary`的属性大概弄清楚了
![](https://p1-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/384cb61dab274776aa4edb4a20b9b325~tplv-k3u1fbpfcp-watermark.image)

# `rawKeys`与`rawValues`

我们很快能发现我们所需要的`keys`和`values`，但他们定义的都是指针，难道拿到指针所指向的地址，就能拿到我们想要的么？

我们看下内存：
![](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/3da8a83f3df346dd8395fbebca04f793~tplv-k3u1fbpfcp-watermark.image)

我们打印的大一点，发现的确有，`31`、`32`、`33`、`34`表示的就是字符串`1`、`2`、`3`、`4`，但似乎和我们想象中的不一样，他们并没有紧挨着靠着起始位置，顺序也是乱的。要解释这个，不得不说`Dictionary`的实现原理哈希表。

# 哈希表算法通俗理解

这段完全摘自别人的[稿子](https://blog.csdn.net/u013752202/article/details/51104156)，因为真得很通俗（偷个懒）。

## 顺序查表法

假设现在有1000个人的档案资料需要存放进档案柜子里。要求是能够快速查询到某人档案是否已经存档，如果已经存档则能快速调出档案。如果是你，你会怎么做？最普通的做法就是把每个人的档案依次放到柜子里，然后柜子外面贴上人名，需要查询某个人的档案的时候就根据这个人的姓名来确定是否已经存档。但是1000个人最坏的情况下我们查找一个人的姓名就要对比1000次！并且人越多，最大查询的次数也就越多，专业的说这种方法的时间复杂的就是O(n)，意思就是人数增加n倍，那么查询的最大次数也就会增加n倍！这种方法，人数少的时候还好，人数越多查询起来就越费劲！那么有什么更好的解决方法吗？答案就是散列表算法，即哈希表算法。

## 哈希表算法

假设每个人的姓名笔划数都是不重复的，那么我们通过一个函数把要存档的人姓名笔划数转换到1000以内，然后把这个人的资料就放在转换后的数字指定的柜子里，这个函数就叫做哈希函数，按照这种方式存放的这1000个柜子就叫哈系表(散列表)，人名笔画数就是哈系表的元素，转换后的数就是人名笔划数的哈希值(也就是柜子的序号)。当要查询某个人是否已经存档的时候，我们就通过哈希函数把他的姓名笔划数转化成哈希值，如果哈希值在1000以内，那么恭喜你这个人已经存档，可以到哈希值指定的柜子里去调出他的档案，否则这个人就是黑户，没有存档！这就是哈希表算法了，是不是很方便，只要通过一次计算得出哈希值就可以查询到结果了，专业的说法就是这种算法的时间复杂是O(1)，即无论有多少人存档，都可以通过一次计算得出查询结果！

当然上面的只是很理想的情况，人名的笔划数是不可能不重复的，转换而来的哈希值也不会是唯一的。那么怎么办呢？如果两个人算出的哈希值是一样的，难道把他们都放到一个柜子里面？如果1000个人得出的哈希值都是一样的呢？下面有几种方法可以解决这种冲突。 

## 开放地址法

这种方法的做法是，如果计算得出的哈希值对应的柜子里面已经放了别人的档案，那么对不起，你得再次通过哈希算法把这个哈希值再次变换，直到找到一个空的柜子为止！查询的时候也一样，首先到第一次计算得出的哈希值对应的柜子里面看看是不是你要找的档案，如果不是继续把这个哈希值通过哈希函数变换，直到找到你要的档案，如果找了几次都没找到而且哈希值对应的柜子里面是空的，那么对不起，查无此人！

## 拉链法(链地址法)

这种方法的做法是，如果计算得出的哈希值对应的柜子里面已经放了别人的档案，那也不管了，懒得再找其他柜子了，就跟他的档案放在一起！当然是按顺序来存放。这样下次来找的时候一个哈希值对应的柜子里面可能有很多人的档案，最差的情况可能1000个人的档案都在一个柜子里面！那么时间复杂度又是O(n)了，跟普通的做法也没啥区别了。在算法实现的时候，每个数组元素存放的不是内容而是链表头，如果哈希值唯一，那么链表大小为1，否则链表大小为重复的哈希值个数。

# 哈希表算法计算机中的理解

哈希表（Hash table，也叫散列表），是根据关键码值(Key value)而直接进行访问的数据结构。也就是说，它通过把关键码值映射到表中一个位置来访问记录，以加快查找的速度。这个映射函数叫做散列函数，存放记录的数组叫做散列表。

## 散列函数

散列函数是一种函数（像`y=f(x)`），经典的散列函数有以下特性:
* 输入域是无穷大的
* 输出域是有穷尽的
* 输入相同，得到的输出也相同
* 因为输入域是远远大于输出域的，那么一定会出现不同的输出，却得到相同的输出，这个叫哈希碰撞
* 满射性：结果尽可能充分覆盖整个输出域
* 最重要的一点：离散性，如果你的样本数量足够大，那么所有的结果在输出域上几乎是均匀分布的

常用的散列函数有：直接定址法、求余法、数字分析法、平方取中法、折叠法、随机数法等，这些方法简单的讲两个：

* 求余法：
Hash(key)=key%M，M通常是散列表规模，M尽可能用素数，因为如果，key都是10的倍数，而M是10，那岂不是都在0上了。。。

* 平方取中法：
首先算出key2，截取中间若干数位作为地址，比如hash(123)=512,因为1232=15129，取中间三位。那为什么要倾向于保留居中的数位呢，这正是为了使得构成原关键码的各个数位，能够对最终的散列地址有尽可能接近的影响。
![](https://p6-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/b7601a309f1c49de949fb9614a6111ca~tplv-k3u1fbpfcp-watermark.image)

但这些方法就不多说了，因为这些都是数学上的方法，了解一下即可。我们编程语言会帮我们预置一些哈希函数，比如：`MD5`、`SHA1`、`SHA256`等。

但这些函数的输出域都比较大，比如`MD5`，它的大小是32位的16进制数，非常大，而我们的哈希表规模会比较小，和你的数据量有关，那怎么办呢？

这里有个推论：因为哈希函数`Hash(key)`具有满射性和离散性，那么`Hash(key)%M`也具有满射性和离散性

所以我们只要取模就行了，其实`Hash(key)%M`本身也是一个哈希函数哈 = =。

哈希函数在计算行业里有很多应用，除了我们现在在了解哈希表外，比如我们经常听见的数字签名，服务器为了负载均衡而做的一致性哈希设计，搜索服务用的布隆过滤器等，都是用的哈希函数的特性。

## 哈希碰撞

哈希表的设计非常棒，他让我们查找数据变成了O(1)的复杂度。但是有个问题需要解决，就是哈希函数会发生碰撞，如何设计解决这个问题，将会决定字典的效率。我们在这里讨论最常见的两种方法：分离链接法和开放定址法

### 分离链接法(Separate Chaining)
俗称拉链法，这个方法会比较好理解，给一张图大概就能理解了
![](https://p1-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/68214a7b56b04d7bb92eb149f8347776~tplv-k3u1fbpfcp-watermark.image)

如果这个长条是整个散列表，那么其中的每一个单元都将各自拥有一个对应的链表，而每一个链表都可以用来存放一组彼此冲突的词条，这就是所谓的分离链接法。

这样就能很好的解决哈希冲突的问题，保证了插入删除元素的常数时间，可以解决任意多次的冲突，但是遗留了一些问题：
* 链表需要引入额外的指针，而为了生成或销毁节点，也需要借助动态内存的申请。相对于常规的操作，此类动态申请操作的时间成本大致要高出两个数量级。
* 链表中各节点的插入和销毁次序完全是随机的。因此对于任何一个链表而言，其中的节点在物理空间上，往往不是连续分布的。那系统很难预测你的访问方向了，无法通过有效的缓存加速查找过程。当散列表的规模非常之大，以至于不得不借助IO时，这一矛盾就显得更加突出了。

在`JAVA`中，解决方案是在链表增长到一定程度时，会换成红黑树储存。这个在这里不是重点，我要引出的是另一个解决哈希碰撞的方法：开放定址法

### 开放定址法——线性探测`(Linear Probing)`

线性探测`(Linear Probing)`是开放定址法的一种，因为我们`Swift`中的哈希表解决冲突用的就是这个方法，我们着重讲这个设计（大部分[转载大佬的](https://www.cnblogs.com/hongshijie/p/9419387.html)）。

那什么叫开放定址法呢？我们前面讲的分离链接法也被称为封闭定址法，他们有什么区别呢？

我们习惯把哈希表中每个单元称之为桶`(bucket)`，在分离链接法中，每个词条应该属于哪个桶所对应的链表，都是在事先已经注定的。每个词条经过一个确定的哈希函数，只会掉确定的桶里，它不可能被散列到其他的桶单元，而开放定址法会被散列到其他的桶单元，这个就是开放和封闭的区别。

分离链接法的缺点，我们前面说过了，那如何解决呢？我们可以反其道而行之，仅仅依靠基本的散列表结构，就地排解冲突反而是更好的选择。也就是采用所谓的开放定址策略，它的特点在于：散列表所占用的空间在物理上始终是地址连续的一块，相应的所有的冲突都在这块连续空间中加以排解。而无需向分离链接那样申请额外的空间。对！所有的散列以及冲突排解都在散列表这样一块封闭的空间内完成。

因此相应地，这种策略也可以称作为闭散列。如果有冲突发生，就要尝试选择另外的单元，直到找到一个可供存放的空单元。具体存放在哪个单元，是有不同优先级的，优先级最高的是他原本归属的那个单元。从这个单元往后，都按照某种优先级规则排成一个序列，而在查找的时候也是按着这个序列行进，每个词条对应的这个序列被称为探测序列or查找链。

抽象来说，就是我们遇到冲突后，会相继尝试h0(x),h1(x),h2(x)这些单元，其中hi(x)= ( Hash( x ) + F ( I ) ) % TableSize，并且约定F(0)=0，F（x）是解决冲突的方法，就是刚才说的那个“优先级规则”。因为所有的数据都要放在这块空间，所以开放定址所需要的表规模比分离链接要大。通常而言开放定址法的装填因子lambda应该低于0.5。而根据对不同F(x)的选择，学界划分出三种常用的探测序列：线性探测法、平方探测法、双散列。

在线性探测法中，函数F是关于i的线性函数，典型的情形是F(i)=i。这相当于逐个探测每个单元（必要时可以绕回）以查找出一个空单元。下面显示了将{89,18,49,58,69}插入到一个散列表中的情况（竖着看），使用了和之前一样的散列函数hash(x)=x%size，他们有冲突怎么办？用F(i)=i这个方法，每次从i=0开始尝试，那么根据hi(x)= ( Hash( x ) + F ( I ) ) % TableSize就可以计算出各自不相冲突的地址了。
![](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/1af0c54d5a44428bac219fe482a1f7ec~tplv-k3u1fbpfcp-watermark.image)

我们脑内单步调试一下：第一个冲突在49产生:（49%10+0）%10=9，被89占了，那接着往后试，i=1，（49%10+1）%10=0，空的，放入这个空闲地址，这个地址是开放的。58依次和18,89,49产生冲突，试选三次后才找到一个空单元。对69的冲突也如此解决，一旦冲突，试探紧邻其后的单元，直至找到空单元or抵达散列表末尾。线性探测序列0->1->2->3在物理上保持连贯性的，具有局部性，这样一来系统的缓存作用将得到充分发挥，而对于大规模的数据集，这样一来更是可以减少I/O的次数。只要表足够大，总能找到一个空闲单元，但是这太费时间了。更糟的是——就算一开始空闲区域多，经过多次排解冲突后，数据所占据的单元也会开始形成一些区块，聚集在一起，被称为一次聚集(primary clustering)，但散列函数的初衷是避免数据扎堆，所以后面必须改进。

那么总体看来散列到区块的任何关键字都需要多次试选单元才能解决冲突，然后被放到对应的那个区块里。下面做一个总结:

优点：

* 无需附加空间（指针、链表、溢出区）
* 探测序列具有局部性，可以利用系统缓存，减少IO

缺点：

* 耗费时间>O(1)
* 冲突增多——以往的冲突会导致后续的连环冲突，发生惨烈的车祸

举个例子吧，这样感触更深。我们开一个size=7的散列表，也保证了size是素数。把{0，1，2，3，7}，就按这个顺序依次插入。前四个数都没问题，依次插入没有冲突。 ![](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/fdd4f8068b534b1b8726f80c460b762d~tplv-k3u1fbpfcp-watermark.image)

但是为了插入7，我们先试探0发现非空，往后走，依次试探1,2,3都非空，直到4可以放进去。
![](https://p9-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/1fa6fab154ec43958b8509d88dc80d5b~tplv-k3u1fbpfcp-watermark.image)

在这个散列表的生存期里只有1个发生冲突。看似很棒对吧，再来看另一插入次序：{7，0，1，2，3}。
![](https://p1-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/9f9a1395bf13436395134805363e87c5~tplv-k3u1fbpfcp-watermark.image)

插入7没问题，但插入0的时候就有冲突了，实际上自此之后每一个数插入都会遇到冲突，前后对比可以看出，第二种插入顺序发生的很多冲突本来是可以避免的。这个时候想必我们改进这种策略的意愿就十分迫切了。

我们仔细来推敲一下，虽然刚才从感性认识的角度，我们能察觉到线性探测是有必要改进的，因为：我们能感知到，表中已有元素越多，新插入时需要探测的次数就越多，这貌似不是个好兆头。但是用数学背景作为背书才是有说服力的。（下面可能有点难以理解，但尽量试着理解吧）

对于随机冲突的解决方法而言，可以假设每次探测与之前的探测无关，这是成立的，因为随机。并且假设有一个很大规模的表，先计算单次失败查找的期望探测次数——这也是找到一个空单元的期望次数。已知空单元所占比例是1-λ，那么预计需要探测的单元数量是1/(1-λ)。因此我们可以使用单次失败查找的开销来计算查找成功的平均开销。

 

这句话的内在逻辑是这样的“失败查找的探测次数=插入时探测次数=查找成功的探测次数”，看似挺矛盾的，我一开始也不太理解，但我们仔细分析一下就能认识到它的道理：首先，右式，一次成功查找的探测次数就等于这个元素插入的探测次数，这个不难理解，插入的时候探测n次，然后放入空单元；之后查找时也是探测n次，第n+1次探测直接命中，两者相等。然后说左式，在插入之前，即将插入时的的探测次数=失败查找的探测次数，因为插入前没有这个元素，自然查找失败。所以左式=右式，这就能大概理解了吧。

还有一件事，早期的λ比较小，所以造次插入开销较低，从更降低了平均开销。比如在上面那个表中，λ=0.5。

![](https://p9-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/328b21ed1a0d4745a343e0100782794d~tplv-k3u1fbpfcp-watermark.image)

访问18的开销是在18被插入时确定的，此时λ=0.2，而由于18是插入到一个比较稀疏的表中，因此对他的访问比更晚插入的元素（e.g. 69）更容易。我们可以通过积分来估计平均的插入时间：
![](https://p9-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/28f470d7e45a4f36861222cf748852d6~tplv-k3u1fbpfcp-watermark.image)

这就比之前线性探测的公式更好了，另外，聚集这个问题，不仅是理论上棘手，在具体实现中也时隐时现，就像幽灵一样。一个幽灵，数据聚集的幽灵，在开放定址表里徘徊。为了对这个幽灵进行神圣的围剿，学界的一切势力，计算机科学家，数学家，还有各路工程师都联合起来了。（这个幽灵的确也为散列理论的创新发展提供了动力，是有一定进步意义的）

我们再来看，如果λ=0.75,那么上面的公式指出，线性探测中1次插入预计要进行8.5次探测。如果λ=0.9，你猜猜我们要找多少次能找到空单元？50次！这绝对不合理。从这些公式我们可以窥见：如果整个表>50%的区域被填满，那么线性探测就不是个好办法。但另一方面，如果是个稀疏表，λ很小，那么线性探测可谓如鱼得水了——我们就算按这个“小”的概念里撑死了说，λ=0.5，插入时平均只用探测…..猜猜….2.5次！，并且对于成功查找平均只需要探测1.5次，酷不酷！ 要以时间条件地点为转移。

讲到这线性探测就讲完了（大佬发言完毕，🎉）

### 总结
解决哈希冲突，传统的拉链法效率上会有一定的缺陷，所以采用开放定址法，我们`Swift`中用的是线性探测。

开放定址法简单点讲，就是在你发生哈希冲突的时候，不去开辟新的空间存放冲突的词条，而是存在你哈希表其他空的桶里。但是你需要定一个规则来探测空桶，比如每次发生碰撞，你优先找当前桶的下个桶存放，如果下个桶已经存放词条，那么在找下下个桶，直到找到空桶存放。这个规则也可以定为找上一个桶，也可以一个桶隔着一个桶找。骚气点的，你可以取你当前桶的下标值做平方，然后再次以表大小取余的值来找空桶，再次用哈希函数找空桶也是不错的方法。

这个探测规则其实相当于一个函数了，如果这个函数是线性的，那么被称为线性探测。开放定址法会占用别人的桶，不难想象，当词条数量达到一定程度的时候，效率会直线下降，需要把哈希表扩容。所以数据量和哈希表大小息息相关，具体的比例前面大佬说过了。（拉链法数据多了，也是需要扩容的）

我们接下来看下`Dictionary`中源码是如何实现哈希表的

# `Dictionary`的初始化函数

我们可以通过生成[`SIL`文件](https://juejin.cn/post/6904994620628074510)
查看得知`Dictionary`的初始化函数：
```swift
  %39 = function_ref @Swift.Dictionary.init(dictionaryLiteral: (A, B)...) -> [A : B] : $@convention(method) <τ_0_0, τ_0_1 where τ_0_0 : Hashable> (@owned Array<(τ_0_0, τ_0_1)>, @thin Dictionary<τ_0_0, τ_0_1>.Type) -> @owned Dictionary<τ_0_0, τ_0_1> // user: %40
```
所以我们在源码中运行代码，并打上断点调试
```swift
  public init(dictionaryLiteral elements: (Key, Value)...) {
  // 生成一个_NativeDictionary对象
    let native = _NativeDictionary<Key, Value>(capacity: elements.count)
    //遍历整个词条
    for (key, value) in elements {
   //在native对象中调用find方法，寻找桶bucket，found是bool值
      let (bucket, found) = native.find(key)
      //初始化中，如果found是yes，说明有重复的元素，编译器会报错，不信你自己试下，会报错下面的提示
      _precondition(!found, "Dictionary literal contains duplicate keys")
      //把词条插入桶中
      native._insert(at: bucket, key: key, value: value)
    }
    //自己的初始化方法
    self.init(_native: native)
  }
```

我们简单看下`Bucket`的结构：
```swift
internal struct Bucket {
    internal var offset: Int
}
```
非常简单，你可以直接理解成`var offset: Int`，相当于数组下标了。

找到初始化方法后，我们要明确下自己的目标，就是找到核心`HashTable`在哪。

如果你断点一路往下走，你会在`_DictionaryStorage`申请堆空间的时候，看到如下代码：

```swift
static internal func allocate(
    scale: Int8,
    age: Int32?,
    seed: Int?
) -> _DictionaryStorage {
    // The entry count must be representable by an Int value; hence the scale's
    // peculiar upper bound.
    _internalInvariant(scale >= 0 && scale < Int.bitWidth - 1)
    
    let bucketCount = (1 as Int) &<< scale
    let wordCount = _UnsafeBitset.wordCount(forCapacity: bucketCount)
    let storage = Builtin.allocWithTailElems_3(
        _DictionaryStorage<Key, Value>.self,
        wordCount._builtinWordValue, _HashTable.Word.self,
        bucketCount._builtinWordValue, Key.self,
        bucketCount._builtinWordValue, Value.self)
    
    let metadataAddr = Builtin.projectTailElems(storage, _HashTable.Word.self)
    let keysAddr = Builtin.getTailAddr_Word(
        metadataAddr, wordCount._builtinWordValue, _HashTable.Word.self,
        Key.self)
    let valuesAddr = Builtin.getTailAddr_Word(
        keysAddr, bucketCount._builtinWordValue, Key.self,
        Value.self)
    storage._count = 0
    storage._capacity = _HashTable.capacity(forScale: scale)
    storage._scale = scale
    storage._reservedScale = 0
    storage._extra = 0
    
    if let age = age {
        storage._age = age
    } else {
        // The default mutation count is simply a scrambled version of the storage
        // address.
        storage._age = Int32(
            truncatingIfNeeded: ObjectIdentifier(storage).hashValue)
    }
    
    storage._seed = seed ?? _HashTable.hashSeed(for: storage, scale: scale)
    storage._rawKeys = UnsafeMutableRawPointer(keysAddr)
    storage._rawValues = UnsafeMutableRawPointer(valuesAddr)
    
    // Initialize hash table metadata.
    storage._hashTable.clear()
    return storage
}
```

我们又一次看到`allocWithTailElems_`，这个函数的意思是，除了给当前对象本身开辟堆空间，也会为尾部跟着的元素开辟新的空间，所以他们连着的，这个等你看完`HashTable`结构后自己验证。`_DictionaryStorage`、`_HashTable.Word`、`Key`、`Value`在内存上是紧挨着的。

这里我们也看到了桶`bucket`的个数，也就是`HashTable`的规模：
```swift
let bucketCount = (1 as Int) &<< scale
storage._scale = scale
```
`bucketCount`由`scale`位移获得，而`scale`也赋值给了`_DictionaryStorage`的`scale`，所以我们在前面`_DictionaryStorage`内存结构中获取`scale`后，通过同样的运算就能获得`bucketCount`

那最初的`scale`是函数外部传进来的，那是如何得到这个数的呢？这个疑问先放一下，先看下我们找到的`HashTable`


# `HashTable`的探索
```swift

internal struct _HashTable {
// 源码追寻下去，Word就是UInt
  internal typealias Word = _UnsafeBitset.Word

  internal var words: UnsafeMutablePointer<Word>

  internal let bucketMask: Int

  internal init(words: UnsafeMutablePointer<Word>, bucketCount: Int) {
    _internalInvariant(bucketCount > 0 && bucketCount & (bucketCount - 1) == 0,
      "bucketCount must be a power of two")
    self.words = words
    // The bucket count is a power of two, so subtracting 1 will never overflow
    // and get us a nice mask.
    self.bucketMask = bucketCount &- 1
  }
  ...
}
```

结构很简单，一共就两个属性，其中`words`存放的就是`HashTable`桶的指针，指向的内容以`UInt`展示，看源码不难发现这个指针指向的地方紧跟着`_DictionaryStorage`内容，我们看`_DictionaryStorage`如何得到`_HashTable`的
```swift
  internal final var _bucketCount: Int {
    @inline(__always) get { return 1 &<< _scale }
  }
  
  internal final var _metadata: UnsafeMutablePointer<_HashTable.Word> {
    @inline(__always) get {
      let address = Builtin.projectTailElems(self, _HashTable.Word.self)
      return UnsafeMutablePointer(address)
    }
  }

  internal final var _hashTable: _HashTable {
    @inline(__always) get {
      return _HashTable(words: _metadata, bucketCount: _bucketCount)
    }
  }
```
这个指针来自`Builtin.projectTailElems`，得到就是`_DictionaryStorage`尾部内容的指针。

`HashTable`是如何用`UInt`来表示桶`bucket`的呢？其实这个和`BitMap`一样，用`UInt`的每个`Bit`位表示一个桶，当`Bit`位等于0的时候，说明是空桶，如果是1，那么表示该位置存在元素

说完了`words`后，我们看下另一个属性`bucketMask`，我们看到初始化赋值的时候，有个表达式`bucketCount &- 1`，那这个有什么意义呢？

前面我们说过了，如果`key`用哈希函数（比如`MD5`）得到了一个很大的哈希值，可以用取余的方式缩小哈希函数的输出域，在哈希表中，可以模上哈希表的大小，这样新得到的哈希值就能均匀的分布到哈希表上。但是，在计算机中模运算是运算中消耗最大的，有没有办法优化呢？这个就是`bucketMask`存在的意义。

先打一个比方，在十进制中，除数是`10000`，如何得到`123456`的余数。怎么办呢？一种方法就是老老实实算，得到答案`3456`，但聪明的你一定不会这么做，直接取数字的后四位，就能得到答案。原因就不说了，在十进制中，只要除数是`10`的倍数，都可以用这个方法。

同理，在二进制中，只要除数是`2`的倍数，那么就可以用上述方法求得余数。比如除数同样是`10000`，不过这个数是二进制表示的，相当于十进制的`16`，是`2`的倍数。那如何取`110011010`的余数呢？除了算，我们还可以用上面一样的方法，取最后的四位数`1010`，就是`110011010`的余数。

方法知道了，我们如何用计算机表达呢？我们可以直接用`110011010`和`1111`做与运算，就能取到后面四位数，而且位运算的效率是很高的。而`1111`与除数`10000`只相差1，看到这，有没有明白了什么？换而言之，在计算机中，如果一个数是`2`的倍数，作为除数的话，那么求任何数的余数，只要将该除数减一，然后和要求的数做与运算就能获得余数。

回到`bucketMask`中，`bucketMask`等于`bucketCount &- 1`，只要`bucketCount`满足是2的倍数，那么`bucketMask`就是当作是给取余的标记使用，任何大的哈希值与上`bucketMask`就能映射到哈希表上。而`bucketCount`等于`1 &<< _scale`，恰好是2的倍数。同样，我们也知道了`_scale`的作用，就是获取哈希表大小的，哈希表的规模也一定是2的倍数。

# 哈希表的规模

看了上文我们得知，哈希表的规模`bucketCount`是`1 &<< _scale`这样获得的，那么`scale`是如何得到的呢？直接看源码：
```swift
/// The inverse of the maximum hash table load factor.
  private static var maxLoadFactor: Double {
    @inline(__always) get { return 3 / 4 }
  }

  internal static func capacity(forScale scale: Int8) -> Int {
    let bucketCount = (1 as Int) &<< scale
    return Int(Double(bucketCount) * maxLoadFactor)
  }

  internal static func scale(forCapacity capacity: Int) -> Int8 {
    let capacity = Swift.max(capacity, 1)
    // Calculate the minimum number of entries we need to allocate to satisfy
    // the maximum load factor. `capacity + 1` below ensures that we always
    // leave at least one hole.
    let minimumEntries = Swift.max(
      Int((Double(capacity) / maxLoadFactor).rounded(.up)),
      capacity + 1)
    // The actual number of entries we need to allocate is the lowest power of
    // two greater than or equal to the minimum entry count. Calculate its
    // exponent.
    let exponent = (Swift.max(minimumEntries, 2) - 1)._binaryLogarithm() + 1
    _internalInvariant(exponent >= 0 && exponent < Int.bitWidth)
    // The scale is the exponent corresponding to the bucket count.
    let scale = Int8(truncatingIfNeeded: exponent)
    _internalInvariant(self.capacity(forScale: scale) >= capacity)
    return scale
  }
```
`scale`的获得，就是存粹的数学运算，在前面字典的初始化方法中，`capacity`传进来的是字典的词条个数。后面扩容的话，可能传进来的是字典的`capacity`（这个是我猜测，没有看源码哦）。

# `Word`字段的个数

前面开辟空间的时候有个细节没有讲：
```swift
let storage = Builtin.allocWithTailElems_3(
        _DictionaryStorage<Key, Value>.self,
        wordCount._builtinWordValue, _HashTable.Word.self,
        bucketCount._builtinWordValue, Key.self,
        bucketCount._builtinWordValue, Value.self)
```

`bucketCount`我们已经知道了，那么`wordCount`的大小是多少呢？

`_HashTable.Word`前面提到过，就是`UInt`，用`UInt`的`bit`位当作桶`bucket`。而`UInt`是8个字节大小，也就是64个`bit`位，一个`UInt`最多当成64个桶，所以存在一个规模比64大的哈希表，1个`_HashTable.Word`肯定记录不了，需要`wordCount`个`_HashTable.Word`，那么`wordCount`怎么求呢？

`wordCount`和`scale`一样，也是存粹的运算，不过我在把`Dictionary`底层翻译成`swift`实现的时候用到了`wordCount`，所以直接贴翻译后的代码了：
```swift
mutating func getWordCount() -> Int {
        let bucketCount = (1 as Int) &<< scale
        let kElement = bucketCount &+ UInt.bitWidth &- 1
        let element = UInt(bitPattern: kElement)
        let capacity = UInt(bitPattern: UInt.bitWidth)
        return Int(bitPattern: element / capacity)
    }
```

# `Dictionary`底层的线性探测(Linear Probing)

我们先来看`Dictionary`查找`Key`在哪个桶的核心方法，断点很容易找到的：

```swfit
internal final func find<Key: Hashable>(_ key: Key, hashValue: Int) -> (bucket: _HashTable.Bucket, found: Bool) {
    //获取hashTable对象
    let hashTable = _hashTable
    //获取key的hash值在hashTable中对应的桶，也就是下标
    var bucket = hashTable.idealBucket(forHashValue: hashValue)
    //遍历，判断条件是这个桶在是否存在值
    while hashTable._isOccupied(bucket) {
        //判断当前桶存放的key与要找的key是否一致
        if uncheckedKey(at: bucket) == key {
            // 找到key，返回true，并且返回key所在桶的位置
            return (bucket, true)
        }
        // 线性探测，获取下一个目标桶的位置
        bucket = hashTable.bucket(wrappedAfter: bucket)
    }
    // 没有找到key，bool值返回false，并且返回这个key应该放入的桶的位置
    return (bucket, false)
}
```
我们在代码中看到，如果发生了哈希碰撞，会调用`hashTable.bucket(wrappedAfter: bucket)`，来寻找下个可以存放的桶，看下他的实现：
```swift
internal func bucket(wrappedAfter bucket: Bucket) -> Bucket {
    // The bucket is less than bucketCount, which is power of two less than
    // Int.max. Therefore adding 1 does not overflow.
    return Bucket(offset: (bucket.offset &+ 1) & bucketMask)
  }
```

我们看到，获取新的`Bucket`并没有开辟新的空间，只是简单的做了加1操作。这个很明显是开放定址法，而且是线性探测序列。


# 写时复制

这个数组的原理一样，也调用引用计数的分析
```swift
@inlinable
  internal mutating func setValue(_ value: __owned Value, forKey key: Key) {
#if _runtime(_ObjC)
    if !isNative {
      // Make sure we have space for an extra element.
      let cocoa = asCocoa
      self = .init(native: _NativeDictionary<Key, Value>(
        cocoa,
        capacity: cocoa.count + 1))
    }
#endif
// 写时复制的引用判断
    let isUnique = self.isUniquelyReferenced()
    asNative.setValue(value, forKey: key, isUnique: isUnique)
  }
```

详细的在[数组](https://juejin.cn/post/6931236309176418311)篇讲过了，这里就不再详细讲述了。


# 结语

本文已经把`Dictionary`底层的大致原理已经讲完了，除了`key`是如何做哈希的，因为源码中用的是私有属性，这个私有属性用到了我们结构里的属性`seed`，整个讲解的话，内容太多了，你可以简单的理解成`MD5`就行了，并不影响内容的理解。

老样子，我把`Dictionary`底层翻译成了`swift`，并且把所有的`Key`、`Value`打印了出来，感兴趣的可以看下，[GitHub地址](https://github.com/harryphone/SwiftDictionaryLayout)。



# 参考文献

* [开放定址法——线性探测(Linear Probing)](https://www.cnblogs.com/hongshijie/p/9419387.html)
* [哈希表算法通俗理解和实现](https://blog.csdn.net/u013752202/article/details/51104156)
* [哈希表（散列表）原理详解](https://blog.csdn.net/duan19920101/article/details/51579136/)
