//
//  LogManager.m
//  LogDemo
//
//  Created by Iean on 2017/7/15.
//  Copyright © 2017年 Iean. All rights reserved.
//

#import "LogManager.h"
#import <UIKit/UIKit.h>
#import "SMTPLibrary/SKPSMTPMessage.h"
#import "SMTPLibrary/NSData+Base64Additions.h"

@interface LogManager () <SKPSMTPMessageDelegate>

@end

@implementation LogManager

static LogManager * _instance = nil;

+(instancetype) shareInstance
{
    static dispatch_once_t onceToken ;
    dispatch_once(&onceToken, ^{
        _instance = [[self alloc] init] ;
    }) ;
    
    return _instance ;
}

- (instancetype)init {
    if (self = [super init]) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sendMessage:) name:@"kSendMessage" object:nil];
    }
    return self;
}

- (void)redirectNSLogToDocumentFolder
{
    //如果已经连接Xcode调试则不输出到文件
    //该函数用于检测输出 (STDOUT_FILENO) 是否重定向 是个 Linux 程序方法
//    if(isatty(STDOUT_FILENO)) {
//        return;
//    }
    
    // 判断 当前是否在 模拟器环境 下 在模拟器不保存到文件中
//    UIDevice *device = [UIDevice currentDevice];
//    if([[device model] hasSuffix:@"Simulator"]){
//        return;
//    }
    
    //将NSlog打印信息保存到Document目录下的Log文件夹下
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *logDirectory = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"Log"];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL fileExists = [fileManager fileExistsAtPath:logDirectory];
    if (!fileExists) {
        [fileManager createDirectoryAtPath:logDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"]];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"]; //每次启动后都保存一个新的日志文件中
    NSString *dateStr = [formatter stringFromDate:[NSDate date]];
    NSString *logFilePath = [logDirectory stringByAppendingFormat:@"/%@.log",dateStr];
    
    // 将log输入到文件
    freopen([logFilePath cStringUsingEncoding:NSUTF8StringEncoding], "a+", stdout);
    freopen([logFilePath cStringUsingEncoding:NSUTF8StringEncoding], "a+", stderr);
    
    //未捕获的Objective-C异常日志
    NSSetUncaughtExceptionHandler (&UncaughtExceptionHandler);
}

/*
之前看的时候，对 NSSetUncaughtExceptionHandler(&UncaughtExceptionHandler) 这个用法一知半解，去翻了一下源码，这个方法是在 Foundation 中。

api 中的定义是Changes the top-level error handler ,Sets the top-level error-handling function where you can perform last-minute logging before the program terminates. 通过替换掉最高级别的 handle 方法，可以在程序终止之前可以获取到崩溃信息，并执行相应的操作，比如保存本地，或者上报。

方法调用为：
void NSSetUncaughtExceptionHandler(NSUncaughtExceptionHandler *);

传入的是一个 NSUncaughtExceptionHandler 的指针。

typedef void NSUncaughtExceptionHandler(NSException *exception);

意思就是需要一个 返回 void 并且参数为 NSException *exception 的函数指针。

你想要，那我就给你！

所以下面有个 C 语言的函数，你看这个写法和 OC 的声明也不一样。
*/
void UncaughtExceptionHandler(NSException* exception)
{
    NSString* name = [ exception name ];
    NSString* reason = [ exception reason ];
    NSArray* symbols = [ exception callStackSymbols ]; // 异常发生时的调用栈
    NSMutableString* strSymbols = [ [ NSMutableString alloc ] init ]; //将调用栈拼成输出日志的字符串
    for ( NSString* item in symbols )
    {
        [ strSymbols appendString: item ];
        [ strSymbols appendString: @"\r\n" ];
    }
    
    //将crash日志保存到Document目录下的Log文件夹下
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *logDirectory = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"Log"];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:logDirectory]) {
        [fileManager createDirectoryAtPath:logDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSString *logFilePath = [logDirectory stringByAppendingPathComponent:@"UncaughtException.log"];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"]];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *dateStr = [formatter stringFromDate:[NSDate date]];
    
    NSString *crashString = [NSString stringWithFormat:@"<- %@ ->[ Uncaught Exception ]\r\nName: %@, Reason: %@\r\n[ Fe Symbols Start ]\r\n%@[ Fe Symbols End ]\r\n\r\n", dateStr, name, reason, strSymbols];
    //把错误日志写到文件中
    if (![fileManager fileExistsAtPath:logFilePath]) {
        [crashString writeToFile:logFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }else{
        NSFileHandle *outFile = [NSFileHandle fileHandleForWritingAtPath:logFilePath];
        [outFile seekToEndOfFile];
        [outFile writeData:[crashString dataUsingEncoding:NSUTF8StringEncoding]];
        [outFile closeFile];
    }
    
    //把错误日志发送到邮箱
//     NSString *urlStr = [NSString stringWithFormat:@"mailto://XXXXX@126.com?subject=bug报告&body=感谢您的配合!<br><br><br>错误详情:<br>%@",crashString ];
//     NSURL *url = [NSURL URLWithString:[urlStr stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
//     [[UIApplication sharedApplication] openURL:url];

//    [[NSNotificationCenter defaultCenter] postNotificationName:@"kSendMessage" object:nil userInfo:@[@"message" :crashString]];
    NSDictionary *dic = [NSDictionary dictionaryWithObjectsAndKeys:crashString, @"message", nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"kSendMessage" object:nil userInfo:dic];
}


- (void)sendMessage:(NSNotification *)noti {
    NSString *message = noti.userInfo[@"message"];
    SKPSMTPMessage *mail = [[SKPSMTPMessage alloc] init];
    [mail setSubject:@"我是主题"];  // 设置邮件主题
    [mail setToEmail:@"xxxxxxx@qq.com"]; // 目标邮箱
    [mail setFromEmail:@"lmsun@mo9.com"]; // 发送者邮箱
    [mail setRelayHost:@"smtp.qq.com"]; // 发送邮件代理服务器
    [mail setRequiresAuth:YES];
    [mail setLogin:@"xxxxxxx@1.com"]; // 发送者邮箱账号
    [mail setPass:@"Sxxxxxxxx"]; // 发送者邮箱密码
    [mail setWantsSecure:YES];  // 需要加密
    [mail setDelegate:self];
    
    NSDictionary *plainPart = @{kSKPSMTPPartContentTypeKey : @"text/plain", kSKPSMTPPartMessageKey : message, kSKPSMTPPartContentTransferEncodingKey : @"8bit"};
    
    [mail setParts:@[plainPart]]; // 邮件首部字段、邮件内容格式和传输编码
    [mail send];
}

-(void)messageSent:(SKPSMTPMessage *)message {
    NSLog(@"message:%@", message);
}
-(void)messageFailed:(SKPSMTPMessage *)message error:(NSError *)error {
    NSLog(@"error:%@",error);
}

@end
