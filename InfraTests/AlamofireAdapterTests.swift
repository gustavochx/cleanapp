//
//  InfraTests.swift
//  InfraTests
//
//  Created by Gustavo Henrique Frota Soares on 24/10/21.
//

import XCTest
import Alamofire
import Data

class AlamofireAdapter: HttpPostClient {
    
    private let session: Session
    
    init(session: Session = .default) {
        self.session = session
    }
    
    func post(to url: URL, with data: Data?, completion: @escaping (Result<Data?, HttpError>) -> Void) {
        session.request(url, method: .post, parameters: data?.toJson(), encoding: JSONEncoding.default).responseData { dataResponse in
            
            guard let statusCode = dataResponse.response?.statusCode else {
                return completion(.failure(.noConnectivity))
            }
            
            switch dataResponse.result {
            case .failure: completion(.failure(.noConnectivity))
            case .success(let data):
                switch statusCode {
                    
                case 204:
                    completion(.success(nil))
                case 200...299:
                    completion(.success(data))
                case 401:
                    completion(.failure(.unauthorized))
                case 403:
                    completion(.failure(.forbidden))
                case 400...499:
                    completion(.failure(.badRequest))
                case 500...599:
                    completion(.failure(.serverError))
                default:
                    completion(.failure(.noConnectivity))
                }
            }
        }
    }
}

class AlamofireAdapterTests: XCTestCase {
    
    func test_post_should_make_request_with_valid_url_and_method() {
        
        let testingUrl = makeUrl()
        
        testRequest(data: makeValidData(), timeoutExpected: 1.0) { request in
            XCTAssertEqual(testingUrl, request.url)
            XCTAssertEqual(HTTPMethod.post.rawValue, request.httpMethod)
            XCTAssertNotNil(request.httpBodyStream)
        }
    }
    
    func test_post_should_make_request_with_empty_body() {
        testRequest(data: makeInvalidData(), timeoutExpected: 1.0) { request in
            XCTAssertNil(request.httpBodyStream)
        }
    }
    
    func test_post_should_complete_with_error_when_request_completes_with_error() {
        expect(expectedResult: .failure(.noConnectivity), when: (data: nil, response: nil, error: makeError()))
    }
    
    func test_post_should_complete_with_error_on_all_invalid_cases() {
        expect(expectedResult: .failure(.noConnectivity), when: (data: makeValidData(), response: makeHttpResponse(), error: makeError()))
        expect(expectedResult: .failure(.noConnectivity), when: (data: makeValidData(), response: nil, error: makeError()))
        expect(expectedResult: .failure(.noConnectivity), when: (data: makeValidData(), response: nil, error: nil))
        expect(expectedResult: .failure(.noConnectivity), when: (data: nil, response: makeHttpResponse(), error: makeError()))
        expect(expectedResult: .failure(.noConnectivity), when: (data: nil, response: makeHttpResponse(), error: nil))
        expect(expectedResult: .failure(.noConnectivity), when: (data: nil, response: nil, error: nil))
    }
        
    func test_post_should_complete_with_error_when_request_completes_without_success() {
        expect(expectedResult: .failure(.badRequest), when: (data: makeValidData(), response: makeHttpResponse(statusCode: 400), error: nil))
        expect(expectedResult: .failure(.unauthorized), when: (data: makeValidData(), response: makeHttpResponse(statusCode: 401), error: nil))
        expect(expectedResult: .failure(.forbidden), when: (data: makeValidData(), response: makeHttpResponse(statusCode: 403), error: nil))
        expect(expectedResult: .failure(.serverError), when: (data: makeValidData(), response: makeHttpResponse(statusCode: 500), error: nil))
        expect(expectedResult: .failure(.serverError), when: (data: makeValidData(), response: makeHttpResponse(statusCode: 550), error: nil))
    }
    
    func test_post_should_complete_with_data_when_request_completes_with_success() {
        expect(expectedResult: .success(makeValidData()), when: (data: makeValidData(), response: makeHttpResponse(), error: nil))
    }
    
    func test_post_should_complete_with_data_when_request_completes_with_created() {
        expect(expectedResult: .success(nil), when: (data: nil, response: makeHttpResponse(statusCode: 204), error: nil))
        expect(expectedResult: .success(nil), when: (data: makeValidData(), response: makeHttpResponse(statusCode: 204), error: nil))
        expect(expectedResult: .success(nil), when: (data: makeEmptyData(), response: makeHttpResponse(statusCode: 204), error: nil))
    }
}

extension AlamofireAdapterTests {
    
    func makeSut(file: StaticString = #filePath, line: UInt = #line) -> AlamofireAdapter {
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.protocolClasses = [UrlProtocolStub.self]
        let sut = AlamofireAdapter(session: Session(configuration: sessionConfiguration))
        checkMemoryLeak(for: sut, file: file, line: line)
        return sut
    }
    
    func testRequest(url: URL = makeUrl(),
                     data: Data?,
                     timeoutExpected: TimeInterval,
                     action: @escaping ((URLRequest) -> Void)) {
        
        
        let sut = makeSut()
        let expectation = expectation(description: "waiting url to be called")
        sut.post(to: url, with: data) { _ in expectation.fulfill() }
        var request: URLRequest?
        UrlProtocolStub.observeRequest { request = $0 }
        wait(for: [expectation], timeout: timeoutExpected)
        action(request!)
    }
    
    func expect(expectedResult: Result<Data?, HttpError>, when stub: (data: Data?, response: HTTPURLResponse?, error: Error?), file: StaticString = #filePath, line: UInt = #line) {
        
        let sut = makeSut()
        UrlProtocolStub.simulate(data: stub.data, httpResponse: stub.response, error: stub.error)
        let expectation = expectation(description: "Waiting")
        
        sut.post(to: makeUrl(), with: makeValidData()) { receivedResult in
            switch (expectedResult, receivedResult)  {
            case (.failure(let expectedError), .failure(let receivedError)): XCTAssertEqual(expectedError, receivedError, file: file, line: line)
            case (.success(let expectedData), .success(let receivedData)): XCTAssertEqual(expectedData, receivedData, file: file, line: line)
            default: XCTFail("Expected error got \(expectedResult) instead", file: file, line: line)
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
    }
    
}

class UrlProtocolStub: URLProtocol {
    
    static var emit: ((URLRequest) -> Void)?
    static var data: Data?
    static var error: Error?
    static var response: HTTPURLResponse?
    
    
    static func simulate(data: Data?, httpResponse: HTTPURLResponse?, error: Error?) {
        UrlProtocolStub.data = data
        UrlProtocolStub.response = httpResponse
        UrlProtocolStub.error = error
    }
    
    static func observeRequest(completion: @escaping (URLRequest) -> Void) {
        UrlProtocolStub.emit = completion
    }
    
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }
    
    override func startLoading() {
        UrlProtocolStub.emit?(request)
        
        if let data = UrlProtocolStub.data {
            client?.urlProtocol(self, didLoad: data)
        }
        
        if let response = UrlProtocolStub.response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        
        if let error = UrlProtocolStub.error {
            client?.urlProtocol(self, didFailWithError: error)
        }
        
        client?.urlProtocolDidFinishLoading(self)
    }
    
    override func stopLoading() {}
}
