//
//  WNMesh : NSObject
//  逆向还原：ivar/方法/属性来自二进制元数据
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "PetDFY.h"

@interface WNMesh : NSObject {
    BOOL _multiply;
    unsigned long long _positionOffset;
    unsigned long long _indexCount;
    unsigned long long _vertexCount;
    unsigned int       _maxIndex;
    id<MTLBuffer> _uv;
    id<MTLBuffer> _indices;
    NSString * _texture;
    NSData * _hitIndices;
}

@property (nonatomic) unsigned long long positionOffset;
@property (nonatomic) unsigned long long indexCount;
/// 本网格顶点数（(cols+1)*(rows+1)），用于绘制前做 buffer 区间校验
@property (nonatomic) unsigned long long vertexCount;
/// 本网格索引最大值（= vertexCount-1），uint16 上限 65535
@property (nonatomic) unsigned int maxIndex;
@property (nonatomic, strong) id<MTLBuffer> uv;
@property (nonatomic, strong) id<MTLBuffer> indices;
@property (nonatomic, copy) NSString * texture;
@property (nonatomic) BOOL multiply;
@property (nonatomic, strong) NSData * hitIndices;

- (unsigned long long)positionOffset;
- (void)setPositionOffset:(unsigned long long)arg1;
- (unsigned long long)indexCount;
- (void)setIndexCount:(unsigned long long)arg1;
- (BOOL)multiply;
- (void)setMultiply:(BOOL)arg1;
@end
