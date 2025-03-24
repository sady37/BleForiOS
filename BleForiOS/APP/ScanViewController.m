//
//  ScanViewController.m
//  BleForiOS/APP
//
//  Created on 2025/3/15.
//

#import "ScanViewController.h"
#import "RadarBleManager.h"
#import "SleepaceBleManager.h"
#import "ConfigStorage.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import "ConfigViewController.h"
#import "ConfigModels.h"

// 日志宏定义
#define SCANLOG(fmt, ...) NSLog((@"[ScanViewController] " fmt), ##__VA_ARGS__)

#pragma mark - DeviceTableViewCell 声明

// 设备单元格类 - 用于展示设备信息
@interface DeviceTableViewCell : UITableViewCell

@property (nonatomic, strong) UILabel *deviceNameLabel;        // 设备名称标签
@property (nonatomic, strong) UILabel *macAddressLabel;        // MAC地址标签
@property (nonatomic, strong) UILabel *rssiLabel;              // 信号强度标签
@property (nonatomic, strong) UIView *signalIndicatorView;     // 信号强度指示器

- (void)configure:(DeviceInfo *)device;

@end

#pragma mark - ScanViewController 私有接口

@interface ScanViewController ()

// UI 组件
@property (nonatomic, strong) UITableView *tableView; //显示设备列表
//@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UITextField *filterTextField;
@property (nonatomic, strong) UIButton *scanButton;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UIButton *configButton;          
@property (nonatomic, strong) UILabel *filterLabel;            

// 数据
@property (nonatomic, strong) NSMutableArray<DeviceInfo *> *deviceList;
@property (nonatomic, assign) Productor currentScanModule;
@property (nonatomic, assign) BOOL isScanning;
@property (nonatomic, strong) ConfigStorage *configStorage;
@property (nonatomic, assign) FilterType currentFilterType;
@property (nonatomic, copy) NSString *currentFilterPrefix;
@property (nonatomic, strong) CBCentralManager *centralManager;

@end

#pragma mark - DeviceTableViewCell 实现

@implementation DeviceTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // 初始化设备名称标签
        _deviceNameLabel = [[UILabel alloc] init];
        _deviceNameLabel.font = [UIFont boldSystemFontOfSize:16];
        [self.contentView addSubview:_deviceNameLabel];
        
        // 初始化MAC地址标签
        _macAddressLabel = [[UILabel alloc] init];
        _macAddressLabel.font = [UIFont systemFontOfSize:14];
        _macAddressLabel.textColor = [UIColor darkGrayColor];
        [self.contentView addSubview:_macAddressLabel];
        
        // 初始化信号强度指示器
        _signalIndicatorView = [[UIView alloc] init];
        _signalIndicatorView.layer.cornerRadius = 4;
        _signalIndicatorView.clipsToBounds = YES;
        [self.contentView addSubview:_signalIndicatorView];
        
        // 初始化RSSI标签
        _rssiLabel = [[UILabel alloc] init];
        _rssiLabel.font = [UIFont systemFontOfSize:14];
        _rssiLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:_rssiLabel];
        
        // 设置约束
        [self setupConstraints];
    }
    return self;
}

- (void)setupConstraints {
    // 禁用自动转换约束
    _deviceNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _macAddressLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _signalIndicatorView.translatesAutoresizingMaskIntoConstraints = NO;
    _rssiLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 设置设备名称标签约束
    [NSLayoutConstraint activateConstraints:@[
        [_deviceNameLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
        [_deviceNameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [_deviceNameLabel.widthAnchor constraintEqualToConstant:170]
    ]];
    
    // 设置MAC地址标签约束
    [NSLayoutConstraint activateConstraints:@[
        [_macAddressLabel.topAnchor constraintEqualToAnchor:_deviceNameLabel.bottomAnchor constant:4],
        [_macAddressLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [_macAddressLabel.trailingAnchor constraintEqualToAnchor:_signalIndicatorView.leadingAnchor constant:-8],
        [_macAddressLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-12]
    ]];
    
    // 设置信号强度指示器约束
    [NSLayoutConstraint activateConstraints:@[
        [_signalIndicatorView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_signalIndicatorView.trailingAnchor constraintEqualToAnchor:_rssiLabel.leadingAnchor constant:-4],
        [_signalIndicatorView.widthAnchor constraintEqualToConstant:8],
        [_signalIndicatorView.heightAnchor constraintEqualToConstant:8]
    ]];
    
    // 设置RSSI标签约束
    [NSLayoutConstraint activateConstraints:@[
        [_rssiLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_rssiLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [_rssiLabel.widthAnchor constraintEqualToConstant:60]
    ]];
}

- (void)configure:(DeviceInfo *)device {
    _deviceNameLabel.text = device.deviceName;
    _macAddressLabel.text = device.macAddress ?: @"Unknown";
    _rssiLabel.text = [NSString stringWithFormat:@"%ld dBm", (long)device.rssi]; // Explicit cast to 'long'
    
    // 根据RSSI值设置信号强度指示器颜色
    if (device.rssi > -70) {
        _signalIndicatorView.backgroundColor = [UIColor systemGreenColor]; // 强信号
    } else if (device.rssi > -85) {
        _signalIndicatorView.backgroundColor = [UIColor systemYellowColor]; // 中等信号
    } else {
        _signalIndicatorView.backgroundColor = [UIColor systemRedColor]; // 弱信号
    }
}

@end

#pragma mark - ScanViewController 实现

@implementation ScanViewController

#pragma mark - 初始化方法

- (instancetype)initWithCentralManager:(CBCentralManager *)centralManager {
    self = [super init];
    if (self) {
        _centralManager = centralManager;
        _deviceList = [NSMutableArray array];
        _configStorage = [[ConfigStorage alloc] init];
        _currentScanModule = ProductorRadarQL; // 默认使用雷达模块
        _isScanning = NO;
        _currentFilterType = FilterTypeDeviceName; // 初始化为默认值
    }
    return self;
}

#pragma mark - 生命周期方法

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Scan Devices";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // 初始化UI组件
    [self setupViews];
    [self setupConstraints];
    [self setupActions];
    
    // 检查蓝牙权限
    [self checkBluetoothPermissions];
    
    // 加载设置
    [self loadSettings];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 视图即将出现时可以添加额外逻辑
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // 视图即将消失时停止扫描
    [self stopScan];
}

- (void)dealloc {
    // 确保停止扫描
    [self stopScan];
    
    // 清理资源
    _deviceList = nil;
    _configStorage = nil;
}

#pragma mark - UI 设置

- (void)setupViews {
// 初始化返回按钮
    _backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 13.0, *)) {
        [_backButton setImage:[UIImage systemImageNamed:@"arrow.left"] forState:UIControlStateNormal];
    } else {
        [_backButton setTitle:@"<" forState:UIControlStateNormal];
    }

    [_backButton addTarget:self action:@selector(dismissViewController) forControlEvents:UIControlEventTouchUpInside];
    _backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_backButton];

	// 初始化标题标签
	//_titleLabel = [[UILabel alloc] init];
	//_titleLabel.text = @"Scan Devices";
	//_titleLabel.font = [UIFont boldSystemFontOfSize:18];
	//_titleLabel.textAlignment = NSTextAlignmentCenter;
	//_titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	//[self.view addSubview:_titleLabel];

    // 初始化配置按钮
    _configButton = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 13.0, *)) {
        [_configButton setImage:[UIImage systemImageNamed:@"gearshape"] forState:UIControlStateNormal];
    } else {
        [_configButton setTitle:@"⚙️" forState:UIControlStateNormal];
    }
    [_configButton addTarget:self action:@selector(showConfigDialog) forControlEvents:UIControlEventTouchUpInside];
    _configButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_configButton];
    
    // 初始化分段控制器
    _segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Radar", @"SleepBoard", @"Filter"]];
    _segmentedControl.selectedSegmentIndex = 0;
	if (@available(iOS 13.0, *)) {
	    _segmentedControl.backgroundColor = [UIColor systemBackgroundColor];
	    _segmentedControl.selectedSegmentTintColor = [UIColor systemBlueColor];
	    [_segmentedControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor labelColor]} forState:UIControlStateSelected];
	    [_segmentedControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor labelColor]} forState:UIControlStateNormal];
	}
    [self.view addSubview:_segmentedControl];

	// 初始化过滤标签
	_filterLabel = [[UILabel alloc] init];
	_filterLabel.text = @"FilterDeviceName";
	_filterLabel.font = [UIFont systemFontOfSize:14];
	[self.view addSubview:_filterLabel];
    
    // 初始化过滤文本框
    _filterTextField = [[UITextField alloc] init];
    _filterTextField.placeholder = @"Filter by name, ID, MAC...";
    _filterTextField.borderStyle = UITextBorderStyleRoundedRect;
    _filterTextField.returnKeyType = UIReturnKeySearch;
    _filterTextField.delegate = self;
    [self.view addSubview:_filterTextField];
    
    // 初始化扫描按钮
    _scanButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_scanButton setTitle:@"Scan" forState:UIControlStateNormal];
    [_scanButton setTitle:@"Stop" forState:UIControlStateSelected];
	[_scanButton setTitleColor:[UIColor systemBackgroundColor] forState:UIControlStateNormal]; // 新增
    _scanButton.backgroundColor = [UIColor systemBlueColor]; // 新增
    _scanButton.layer.cornerRadius = 5.0; // 新增
    [self.view addSubview:_scanButton];
  
    // 初始化表格视图
    _tableView = [[UITableView alloc] init];
    [_tableView registerClass:[DeviceTableViewCell class] forCellReuseIdentifier:@"DeviceCell"];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.rowHeight = 50; // 不需要显示历史记录
    _tableView.separatorInset = UIEdgeInsetsMake(0, 16, 0, 16);
    [self.view addSubview:_tableView];

	// 更新过滤提示信息
	[self updateFilterHint];
}

- (void)setupConstraints {
    // 禁用自动转换约束
    _segmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
	_filterLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _filterTextField.translatesAutoresizingMaskIntoConstraints = NO;
    _scanButton.translatesAutoresizingMaskIntoConstraints = NO;
	_configButton.translatesAutoresizingMaskIntoConstraints = NO;
 	_tableView.translatesAutoresizingMaskIntoConstraints = NO;

	// 设置返回按钮的约束
	[NSLayoutConstraint activateConstraints:@[
	    [_backButton.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20], // 距离左边 20 点
	    [_backButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:0], // 距离顶部 10 点
	    [_backButton.widthAnchor constraintEqualToConstant:44], // 宽度设为 44
	    [_backButton.heightAnchor constraintEqualToConstant:44] // 高度设为 44
	]];

	// 设置标题标签的约束
	//[NSLayoutConstraint activateConstraints:@[
    //	[_titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor], // 水平居中
    //	[_titleLabel.centerYAnchor constraintEqualToAnchor:_backButton.centerYAnchor], // 与backButton垂直对齐
	//]];

    // 设置配置按钮的约束
    [NSLayoutConstraint activateConstraints:@[
        [_configButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20], // 距离右边 20 点
        [_configButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:0], // 距离顶部 20 点
        [_configButton.widthAnchor constraintEqualToConstant:44], // 宽度设为 60
        [_configButton.heightAnchor constraintEqualToConstant:44] // 高度设为 60
    ]];

    // 设置分段控制器约束
    [NSLayoutConstraint activateConstraints:@[
		[_segmentedControl.topAnchor constraintEqualToAnchor:_backButton.bottomAnchor constant:5], // 距离 backButton 底部 20 点
        [_segmentedControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:70],//头边距
        [_segmentedControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-70],//尾边距
    ]];
	    
	// 设置过滤标签约束 - 与文本框同行
	[NSLayoutConstraint activateConstraints:@[
	    [_filterLabel.topAnchor constraintEqualToAnchor:_segmentedControl.bottomAnchor constant:16],
	    [_filterLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
   		[_filterLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_filterTextField.leadingAnchor constant:-8], // 自适应宽度
    	[_filterLabel.centerYAnchor constraintEqualToAnchor:_filterTextField.centerYAnchor],
		// 宽度约束
        [_filterLabel.widthAnchor constraintGreaterThanOrEqualToConstant:80], // 最小宽度100
        //[_filterLabel.widthAnchor constraintLessThanOrEqualToConstant:180]    // 最大宽度180
	]];

	// 设置过滤文本框约束（最小100，弹性填充）
	[NSLayoutConstraint activateConstraints:@[
	    [_filterTextField.topAnchor constraintEqualToAnchor:_segmentedControl.bottomAnchor constant:16],
	    [_filterTextField.leadingAnchor constraintEqualToAnchor:_filterLabel.trailingAnchor constant:8],
	    [_filterTextField.trailingAnchor constraintEqualToAnchor:_scanButton.leadingAnchor constant:-8],
		        // 宽度约束
        [_filterTextField.widthAnchor constraintGreaterThanOrEqualToConstant:100] // 最小宽度100
	]];
	    
    // 设置扫描按钮约束
    [NSLayoutConstraint activateConstraints:@[
        [_scanButton.centerYAnchor constraintEqualToAnchor:_filterTextField.centerYAnchor],
        [_scanButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [_scanButton.widthAnchor constraintEqualToConstant:60]
    ]];
    
    // 设置表格视图约束
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:_filterTextField.bottomAnchor constant:16],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];

}

- (void)setupActions {
    // 设置扫描按钮动作
    [_scanButton addTarget:self action:@selector(toggleScan) forControlEvents:UIControlEventTouchUpInside];

	    // 设置配置按钮动作
    [_configButton addTarget:self action:@selector(showConfigDialog) forControlEvents:UIControlEventTouchUpInside];
    
   
    // 设置分段控制器动作
    [_segmentedControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
}

- (void)loadSettings {
    // 加载保存的过滤器类型
    FilterType savedFilterType = [_configStorage getFilterType];
    
    // 验证加载的过滤器类型是否有效
    switch (savedFilterType) {
        case FilterTypeDeviceName:
        case FilterTypeMac:
        case FilterTypeUUID:
            _currentFilterType = savedFilterType;
            break;
        default:
            _currentFilterType = FilterTypeDeviceName; // 默认值
            break;
    }
}

#pragma mark - 蓝牙权限检查

- (void)checkBluetoothPermissions {
    // iOS 13+ 需要显式请求蓝牙权限
    if (@available(iOS 13.0, *)) {
        CBCentralManager *tempManager = [[CBCentralManager alloc] initWithDelegate:nil queue:nil];
        CBManagerState state = tempManager.state;
        
        if (state == CBManagerStateUnauthorized) {
            [self showPermissionAlert];
        }
    }
}

- (void)showPermissionAlert {
    UIAlertController *alert = [UIAlertController 
                                alertControllerWithTitle:@"Bluetooth Permission Required"
                                message:@"This app needs Bluetooth permission to scan for devices. Please enable Bluetooth access in Settings."
                                preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *openSettings = [UIAlertAction 
                                  actionWithTitle:@"Open Settings"
                                  style:UIAlertActionStyleDefault
                                  handler:^(UIAlertAction * _Nonnull action) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]
                                          options:@{}
                                completionHandler:nil];
    }];
    
    UIAlertAction *cancel = [UIAlertAction 
                            actionWithTitle:@"Cancel"
                            style:UIAlertActionStyleCancel
                            handler:nil];
    
    [alert addAction:openSettings];
    [alert addAction:cancel];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 扫描控制

- (void)toggleScan {
    if (_isScanning) {
        [self stopScan];
    } else {
        [self startScan];
    }
}

- (void)updateScanButtonState:(BOOL)scanning {
    _isScanning = scanning;
    [_scanButton setTitle:(scanning ? @"STOP" : @"SCAN") forState:UIControlStateNormal];
    _scanButton.backgroundColor = scanning ? [UIColor systemRedColor] : [UIColor systemBlueColor];
}

- (void)startScan {
    // 根据当前选择的模块获取正确的过滤前缀
    switch (_currentScanModule) {
        case ProductorRadarQL:
            _currentFilterPrefix = [_configStorage getRadarDeviceName];
            _currentFilterType = FilterTypeDeviceName;
            break;
        case ProductorSleepBoardHS:
            // 对于SleepBoard不使用过滤
            _currentFilterPrefix = @"";
            _currentFilterType = FilterTypeDeviceName;
            break;
        case ProductorEspBle:
            _currentFilterPrefix = _filterTextField.text;
            _currentFilterType = [_configStorage getFilterType];
            break;
    }
    
    // 清空设备列表
    [_deviceList removeAllObjects];
    [_tableView reloadData];
    
    // 更新UI状态
    [self updateScanButtonState:YES];
    
    // 开始相应的扫描
    switch (_currentScanModule) {
        case ProductorRadarQL:
        case ProductorEspBle:
            [self startRadarScan];
            break;
        case ProductorSleepBoardHS:
            [self startSleepaceScan];
            break;
    }
}

- (void)stopScan {
    if (!_isScanning) return;
    
    // 停止所有扫描
    [_centralManager stopScan];
    
    // 更新UI状态
    [self updateScanButtonState:NO];
}

- (void)startRadarScan {
    SCANLOG(@"Starting Radar scan with filter prefix: %@, type: %@", 
           _currentFilterPrefix ?: @"None", 
           (long)_currentFilterType == FilterTypeDeviceName ? @"DeviceName" : (_currentFilterType == FilterTypeMac ? @"MAC" : @"UUID"));
    
    // 设置扫描回调
    [_centralManager scanForPeripheralsWithServices:nil options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @NO}];
}

- (void)startSleepaceScan {
    SCANLOG(@"Starting Sleepace scan");
        // 使用 _centralManager 直接扫描
    [_centralManager scanForPeripheralsWithServices:nil options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @NO}];

}

#pragma mark - UITableViewDelegate & UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _deviceList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DeviceTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DeviceCell" forIndexPath:indexPath];
    
    // 获取设备信息
    DeviceInfo *device = _deviceList[indexPath.row];
    
    // 配置单元格
    [cell configure:device];
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 50.0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    

	// 确保索引在有效范围内
	if (indexPath.row < 0 || indexPath.row >= _deviceList.count) {
		NSLog(@"Invalid indexPath.row: %ld", (long)indexPath.row);
		return;
	}
	
	
    // 获取选中的设备
    DeviceInfo *device = _deviceList[indexPath.row];
    
    // 停止扫描
    [self stopScan];
    
    // 添加短暂延迟，确保扫描完全停止
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // 通知代理
        if (self.delegate && [self.delegate respondsToSelector:@selector(scanViewController:didSelectDevice:)]) {
            [self.delegate scanViewController:self didSelectDevice:device];
        }
        
        // 关闭视图
        [self dismissViewControllerAnimated:YES completion:nil];
    });
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    // 延迟更新过滤列表，以便用户输入完成
    dispatch_async(dispatch_get_main_queue(), ^{
        [self filterDevices];
    });
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self filterDevices];
    return YES;
}

#pragma mark - 设备过滤

- (void)filterDevices {
    // 如果过滤文本为空，不进行过滤
    NSString *filterText = _filterTextField.text;
    if (filterText.length == 0) {
        // 重新加载表格
        [_tableView reloadData];
        return;
    }
    
    // 转换为小写进行不区分大小写的搜索
    filterText = [filterText lowercaseString];
    
    // 过滤设备列表
    NSMutableArray<DeviceInfo *> *filteredList = [NSMutableArray array];
    for (DeviceInfo *device in _deviceList) {
        if ([[device.deviceName lowercaseString] containsString:filterText] ||
            [[device.deviceId lowercaseString] containsString:filterText] ||
            (device.macAddress && [[device.macAddress lowercaseString] containsString:filterText])) {
            [filteredList addObject:device];
        }
    }
    
    // 更新设备列表并刷新表格
    _deviceList = filteredList;
    [_tableView reloadData];
}

#pragma mark - 配置管理

/**
 * 更新过滤提示信息
 */
- (void)updateFilterHint {
    // 根据当前过滤类型更新标签和输入框提示
    switch (_currentFilterType) {
        case FilterTypeDeviceName:
            _filterLabel.text = @"FilterDeviceName";
            _filterTextField.placeholder = @"TSBLU,...";
            break;
        case FilterTypeMac:
            _filterLabel.text = @"FilterMAC";
            _filterTextField.placeholder = @"XX:XX:XX:XX:XX:XX";
            break;
        case FilterTypeUUID:
            _filterLabel.text = @"FilterUUID";
            _filterTextField.placeholder = @"XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
            break;
    }
}

/**
 * 显示配置对话框
 */
- (void)showConfigDialog {
    SCANLOG(@"display config dialog");
    
    // 创建并配置ConfigViewController
    ConfigViewController *configVC = [[ConfigViewController alloc] 
                                      initWithRadarDeviceName:_currentFilterPrefix 
                                      filterType:_currentFilterType // Pass enum directly
                                      completion:^(NSString *radarDeviceName, FilterType filterType) {
        // 更新当前配置
        self->_currentFilterPrefix = radarDeviceName;
        self->_currentFilterType = filterType;
        
        // 更新UI
        [self updateFilterHint];
        self->_filterTextField.text = radarDeviceName;
        
        // 保存配置
        [self->_configStorage saveRadarDeviceName:radarDeviceName];
        [self->_configStorage saveFilterType:filterType];
        
        // 如果正在扫描，停止并重新开始
        if (self->_isScanning) {
            [self stopScan];
            [self startScan];
        }
    }];
    
    // 显示配置视图控制器
    [self presentViewController:configVC animated:YES completion:nil];
}

#pragma mark - 其他方法

- (void)segmentChanged:(UISegmentedControl *)sender {
    // 更新当前扫描模块
    switch (sender.selectedSegmentIndex) {
        case 0:
            _currentScanModule = ProductorRadarQL;
            break;
        case 1:
            _currentScanModule = ProductorSleepBoardHS;
            break;
        case 2:
            _currentScanModule = ProductorEspBle;
            break;
        default:
            _currentScanModule = ProductorRadarQL;
            break;
    }
    
    // 如果正在扫描，重新开始扫描
    if (_isScanning) {
        [self stopScan];
        [self startScan];
    }
}

- (void)dismissViewController {
    [self stopScan];
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

@end
