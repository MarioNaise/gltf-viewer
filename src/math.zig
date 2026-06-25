pub const Vec3 = [3]f32;
pub const Quat = [4]f32;
pub const Mat4 = [4][4]f32;

/// Creates a quaternion from a vector of Euler angles (Vec3{x ,y, z})
pub fn quatFromVec(v: Vec3) Quat {
    const qy = quatFromAxisAngle(.{ 0, 1, 0 }, v[1]);
    const qx = quatFromAxisAngle(.{ 1, 0, 0 }, v[0]);
    const qz = quatFromAxisAngle(.{ 0, 0, 1 }, v[2]);

    return quatMul(qz, quatMul(qx, qy));
}

/// Creates a quaternion from an axis and an angle.
pub fn quatFromAxisAngle(axis: Vec3, angle: f32) Quat {
    const half = angle * 0.5;
    const s = @sin(half);

    return .{
        axis[0] * s,
        axis[1] * s,
        axis[2] * s,
        @cos(half),
    };
}

/// Quaternion multiplication.
/// Returns the product of two quaternions a and b, representing the combined rotation.
pub fn quatMul(a: Quat, b: Quat) Quat {
    return .{
        a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
        a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
        a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
        a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
    };
}

pub const identity = Mat4{
    .{ 1, 0, 0, 0 },
    .{ 0, 1, 0, 0 },
    .{ 0, 0, 1, 0 },
    .{ 0, 0, 0, 1 },
};

/// Return 4x4 matrix from given all transform components; `translation`, `rotation` and `scale`.
/// The final order is T * R * S.
pub fn composeMat(translation: Vec3, rotation: Quat, scale: Vec3) Mat4 {
    const t = blk: {
        var mat = identity;
        mat[3][0] = translation[0];
        mat[3][1] = translation[1];
        mat[3][2] = translation[2];

        break :blk mat;
    };

    const r = blk: {
        var result = identity;

        const x = rotation[0];
        const y = rotation[1];
        const z = rotation[2];
        const w = rotation[3];

        const xx = x * x;
        const yy = y * y;
        const zz = z * z;
        const xy = x * y;
        const xz = x * z;
        const yz = y * z;
        const wx = w * x;
        const wy = w * y;
        const wz = w * z;

        result[0][0] = 1.0 - 2.0 * (yy + zz);
        result[0][1] = 2.0 * (xy + wz);
        result[0][2] = 2.0 * (xz - wy);
        result[0][3] = 0.0;

        result[1][0] = 2.0 * (xy - wz);
        result[1][1] = 1.0 - 2.0 * (xx + zz);
        result[1][2] = 2.0 * (yz + wx);
        result[1][3] = 0.0;

        result[2][0] = 2.0 * (xz + wy);
        result[2][1] = 2.0 * (yz - wx);
        result[2][2] = 1.0 - 2.0 * (xx + yy);
        result[2][3] = 0.0;

        result[3][0] = 0.0;
        result[3][1] = 0.0;
        result[3][2] = 0.0;
        result[3][3] = 1.0;

        break :blk result;
    };

    const s = blk: {
        var mat = identity;
        mat[0][0] = scale[0];
        mat[1][1] = scale[1];
        mat[2][2] = scale[2];

        break :blk mat;
    };

    return matMul(t, matMul(r, s));
}

/// Matrices' multiplication.
/// Produce a new matrix from given two matrices.
pub fn matMul(left: Mat4, right: Mat4) Mat4 {
    var result = identity;

    for (result, 0..) |_, column| {
        for (result[column], 0..) |_, row| {
            var sum: f32 = 0;
            var left_column: usize = 0;

            while (left_column < 4) : (left_column += 1) {
                sum += left[left_column][row] * right[column][left_column];
            }

            result[column][row] = sum;
        }
    }

    return result;
}

/// Multiplies a 4x4 matrix with a 3D vector, returning the transformed vector.
pub fn transformVector(model: Mat4, p: Vec3) Vec3 {
    return .{
        model[0][0] * p[0] + model[1][0] * p[1] + model[2][0] * p[2] + model[3][0],
        model[0][1] * p[0] + model[1][1] * p[1] + model[2][1] * p[2] + model[3][1],
        model[0][2] * p[0] + model[1][2] * p[1] + model[2][2] * p[2] + model[3][2],
    };
}
